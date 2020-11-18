<#
.SYNOPSIS
The script goes over directories tree recursively, assigning "Allow FullControl" permission entry to all items it encounters 
that have no such permission for selected user account

.DESCRIPTION
The script is intended to "fix" permissions of the files and folders inside designated directory that has their inheritence
flag disabled and are not allowed to be accessed by LOCAL SYSTEM user. The script will traverse target directory recursively
and add permission entry for FullControl for LOCAL SYSTEM user. Optionally, it can take the ownership of the file first
(this might be necessary sometimes as non-owner in AD environment might not have enough permissions to set permissions).
All successful / unsuccessful permissions attempts are logged in verbose stream, so use -Verbose 4>permisions_fix.log
argument to log per-item results into a log file.
The attempt to take ownership is always done to a user running script and it's advised to run it as a domain admin which is
also a local admin.

.PARAMETER Path
Specify to point the directory to be inspected for missing permissions.

.PARAMETER FilesAmountExpected
Specify approximate amount of files for correct progress bar behavior

.PARAMETER WhatIf
Specify to only show which files are going to be updated and don't do actual changes to filesystem

.PARAMETER TakeOwnership
Specify to force script to take ownership of the object before adding permission entry. Could be useful in some cases 
when non-owner cannot adjust object permissions. Domain admins can ALWAYS take ownership of the object.

.PARAMETER SupportLongPath
Specify to allow script working with paths longer than 260 symbols. Requires powershell 5.1 and newer! Won't work on PS4.

.EXAMPLE
.\fix-permissions.ps1 -Path C:\TestFolders\ -TakeOwnership -Verbose 4>log.txt
will run the scrip to process C:\TestFolders and all its children recursively adding SYSTEM:FullControl permission to all items, assigning current user as an owner and dumping successful/unsuccesful attempts into file log.txt
#>

[CmdletBinding()]
param
(
	[parameter(Mandatory = $true)]
	[String]$Path,
	[int]$FilesAmountExpected = 1000000,
	[switch]$WhatIf,
	[switch]$TakeOwnership,
	[switch]$SupportLongPath
)

# ----------------------------------------------------------------------------------------------------------------------------------------

function Process-Item
{
	param
	(
		[parameter(Mandatory = $true)]
		[String]$PathToItem
	)
	# Place your code here to do something with the item discovered
	$acl = Get-Acl -LiteralPath $PathToItem
	if (!$?)
	{
		Write-Verbose "Unknown: $PathToItem"
		return
	}
	$have_permissions = $false
	foreach ($ace in $acl.Access)
	{
		if ($ace.IdentityReference -like "NT AUTHORITY\SYSTEM" -and $ace.FileSystemRights -like "FullControl" -and $ace.AccessControlType -like "Allow")
		{
			$have_permissions = $true
			break
		}
	}
	if (!$have_permissions)
	{
		if (!$WhatIf)
		{
			if ($TakeOwnership)
			{
				$acl.SetOwner($script:OwnerObject)
				Set-Acl -AclObject $acl -LiteralPath $PathToItem
			}
			$acl.SetAccessRule($Script:AccessRuleObject)
			Set-Acl -LiteralPath $PathToItem -AclObject $acl
			if (!$?)
			{
				$script:UnsuccesfulUpdates++
				Write-Verbose "Failed: `"$PathToItem`""
			}
			else
			{
				Write-Verbose "Succeed: `"$PathToItem`""
			}
		}
		else
		{
			Write-Verbose "Will update: `"$PathToItem`""
		}
		$Script:ItemsUpdated++
	}
}
# ----------------------------------------------------------------------------------------------------------------------------------------

function Traverse-Directory
{
	param
	(
		[parameter(Mandatory = $true)]
		[String]$PathToProcess
	)
	
	$FilesList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes !Directory
	if (!$?) { Write-Error "Failed to GCI: $PathToProcess" }
	$DirsList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes Directory
	if (!$?) { Write-Error "Failed to GCI: $PathToProcess" }
	
	foreach ($file in $FilesList)
	{
		Process-Item $file.FullName
	}
	foreach ($dir in $DirsList)
	{
		Process-Item $dir.FullName
	}
	$script:FileCounter += $FilesList.Count
	$script:DirCounter += $DirsList.Count
	if ($script:FileCounter -gt $FilesAmountExpected) { $FilesAmountExpected += 10000}
	Write-Progress -Activity "Traversing directories recursively" -Status "Processed $($script:FileCounter) files, $($script:DirCounter) directories" -PercentComplete ($script:FileCounter * 100 / $FilesAmountExpected)
	foreach ($dir in $DirsList)
	{
		Traverse-Directory -PathToProcess $dir.FullName
	}
}
# ----------------------------------------------------------------------------------------------------------------------------------------

$FileCounter = 0
$DirCounter = 0
$ItemsUpdated = 0
$UnsuccesfulUpdates = 0
$OwnerObject = New-Object System.Security.Principal.NTAccount("$env:USERDOMAIN", "$env:USERNAME")
$AccessRuleObject = New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "FullControl", "Allow")
if ($SupportLongPath) { $Path = "\\?\$Path" }
Traverse-Directory -PathToProcess $Path
Write-Progress -Activity "Traversing directories recursively" -Completed
Write-Host "Processed total $FileCounter files, $DirCounter dirs. Updated items $($ItemsUpdated-$UnsuccesfulUpdates)/$UnsuccesfulUpdates (success/unsuccess)"
