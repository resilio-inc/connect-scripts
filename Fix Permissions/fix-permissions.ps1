<#
.SYNOPSIS
The script goes over directories tree recursively, assigning "Allow FullControl" permission entry to all items it encounters 
that have no such permission for selected user account

.DESCRIPTION
The script is intended to "fix" permissions of the files and folders inside designated directory that has their inheritence
flag disabled and are not allowed to be accessed by LOCAL SYSTEM user. The script will traverse target directory recursively
and add permission entry for FullControl for target user (LOCAL SYSTEM by default). Also, it will add an explicit "Allow all"
ACE for the user running the script if it is unable to traverse a directory. Optionally, it can take the ownership temporaryly 
of the file/folder if permission assignment fails (this might be necessary sometimes as non-owner in AD environment might not 
have enough permissions to set permissions). All successful / unsuccessful permissions attempts are logged in verbose stream, 
so use -Verbose 4>permisions_fix.log argument to log per-item results into a log file.
The attempt to take ownership is always done to a user running script and it's advised to run it as a domain admin which is
also a local admin.

.PARAMETER Path
Specify to point the directory to be inspected for missing permissions.

.PARAMETER FilesAmountExpected
Specify approximate amount of files for correct progress bar behavior

.PARAMETER WhatIf
Specify to only show which files are going to be updated and don't do actual changes to filesystem. Note that this parameter
prohibits all the changes and therefore script may fail to traverse all directories as sometimes it needs to add a permission
for a running user to traverse the directory

.PARAMETER TakeOwnership
Specify to allow script to take ownership temporarily if it fails to assign allowing ACE. Could be useful in some cases 
when non-owner cannot adjust object permissions. Domain admins can ALWAYS take ownership of the object.

.PARAMETER SupportLongPath
Specify to allow script working with paths longer than 260 symbols. Requires powershell 5.1 and newer! Won't work on PS4.

.PARAMETER TargetUser
Specify to set the target user that will receive ALLOW FULLCONTROL permissions. "LOCAL SYSTEM" is the default value.

.EXAMPLE
.\fix-permissions.ps1 -Path C:\TestFolders\ -TakeOwnership -Verbose 4>log.txt
will run the scrip to process C:\TestFolders and all its children recursively adding SYSTEM:FullControl permission to all items, assigning current user as an owner if necessary and dumping successful/unsuccesful attempts into file log.txt

.NOTES
The script behaves as non-invasive as it is possible. If target folder/file has necessary permissions for the target user AND
has enough permissions for the user running script to traverse further - script does not change anything.
#>

[CmdletBinding()]
param
(
	[parameter(Mandatory = $true)]
	[String]$Path,
	[int]$FilesAmountExpected = 10000000,
	[switch]$WhatIf,
	[switch]$TakeOwnership,
	[switch]$SupportLongPath,
	[string]$TargetUser = "NT AUTHORITY\SYSTEM"
)

# ----------------------------------------------------------------------------------------------------------------------------------------

function Process-Item
{
	param
	(
		[parameter(Mandatory = $true)]
		[String]$PathToItem,
		[switch]$UseCurrentUser,
		[switch]$RemoveDenialACEs,
		[switch]$IsDirectory
	)
	
	if ($IsDirectory)
	{
		$UserAccount = $TargetUser
		$AccessRuleObject = $script:TargetUserAccessRuleObjectForDir
		if ($UseCurrentUser)
		{
			$UserAccount = $script:CurrentUser
			$AccessRuleObject = $script:CurrentUserAccessRuleObjectForDir
		}
	}
	else
	{
		$UserAccount = $TargetUser
		$AccessRuleObject = $script:TargetUserAccessRuleObjectForFile
		if ($UseCurrentUser)
		{
			$UserAccount = $script:CurrentUser
			$AccessRuleObject = $script:CurrentUserAccessRuleObjectForFile
		}
	}
	
	$acl = Get-Acl -LiteralPath $PathToItem
	if (!$?)
	{
		Write-Verbose "Unknown: $PathToItem"
		return
	}
	$acl_update_required = $false
	
	# Search ACL for necessary user account permission "FullControl" -> "Allow"
	$missing_allow_permission = $true
	if ($IsDirectory)
	{
		foreach ($ace in $acl.Access)
		{
			if ($ace.IdentityReference -like $UserAccount -and $ace.FileSystemRights -like "FullControl" -and $ace.AccessControlType -like "Allow" -and $ace.InheritanceFlags -like "*ContainerInherit*" -and $ace.InheritanceFlags -like "*ObjectInherit*")
			{
				$missing_allow_permission = $false
				break
			}
		}
	}
	else
	{
		foreach ($ace in $acl.Access)
		{
			if ($ace.IdentityReference -like $UserAccount -and $ace.FileSystemRights -like "FullControl" -and $ace.AccessControlType -like "Allow")
			{
				$missing_allow_permission = $false
				break
			}
		}
	}
	if ($missing_allow_permission)
	{
		$acl.SetAccessRule($AccessRuleObject)
		$acl_update_required = $true
	}
	
	#Search ACL for any denial entries and wipe them out
	if ($RemoveDenialACEs)
	{
		foreach ($ace in $acl.Access)
		{
			if ($ace.accesscontroltype -eq "Deny")
			{
				$acl.RemoveAccessRule($ace) | Out-Null
				$acl_update_required = $true
			}
		}
	}
	
	if ($acl_update_required)
	{
		if (!$WhatIf)
		{
			$update_success = $false
			$acl.SetAccessRule($AccessRuleObject)
			Set-Acl -LiteralPath $PathToItem -AclObject $acl
			if (!$?)
			{
				if ($TakeOwnership)
				{
					Write-Verbose "Attempting to take ownership for `"$PathToItem`""
					$tmp_acl = Get-Acl -LiteralPath $PathToItem
					$OldOwner = $tmp_acl.Owner.Split('\')
					$OldOwnerObject = New-Object System.Security.Principal.NTAccount($OldOwner[0], $OldOwner[1])
					$tmp_acl.SetOwner($script:OwnerObject)
					Set-Acl -AclObject $tmp_acl -LiteralPath $PathToItem		# Apply new owner
					Set-Acl -LiteralPath $PathToItem -AclObject $acl 			# Apply new acl
					$tmp_acl = Get-Acl -LiteralPath $PathToItem
					$tmp_acl.SetOwner($OldOwnerObject)
					Set-Acl -AclObject $tmp_acl -LiteralPath $PathToItem 		# Return back old owner
					if ($?) {$update_success = $true}
				}
			}
			else { $update_success = $true }
			if ($update_success)
			{
				Write-Verbose "Succeed ($UserAccount): `"$PathToItem`""
			}
			else
			{
				$script:UnsuccesfulUpdates++
				Write-Verbose "Failed ($UserAccount): `"$PathToItem`""
			}
		}
		else
		{
			Write-Verbose "Will update ($UserAccount): `"$PathToItem`""
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
	Write-Host "Processing directory `"$PathToProcess`""
	$FilesList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes !Directory -ErrorAction SilentlyContinue
	if (!$?)
	{
		if ($Error.CategoryInfo.Category -eq "PermissionDenied")
		{
			Process-Item $PathToProcess -UseCurrentUser -RemoveDenialACEs -IsDirectory
			$FilesList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes !Directory
		}
		else
		{
			Write-Error "Failed to list directory: $PathToProcess ($($Error[0].ToString()))"
			Write-Verbose "Failed to list directory: $PathToProcess ($($Error[0].ToString()))"
			exit
		}
	}
	$DirsList = Get-ChildItem -LiteralPath $PathToProcess -Force -Attributes Directory
	
	foreach ($file in $FilesList)
	{
		Process-Item $file.FullName
	}
	foreach ($dir in $DirsList)
	{
		Process-Item $dir.FullName -IsDirectory
	}
	$script:FileCounter += $FilesList.Count
	$script:DirCounter += $DirsList.Count
	if ($script:FileCounter -gt $FilesAmountExpected) { $FilesAmountExpected = $script:FileCounter + 10000}
	Write-Progress -Activity "Traversing directories recursively" -Status "Processed $($script:FileCounter) files, $($script:DirCounter) directories" -PercentComplete ($script:FileCounter * 100 / $FilesAmountExpected)
	foreach ($dir in $DirsList)
	{
		Traverse-Directory -PathToProcess $dir.FullName
	}
}
# ----------------------------------------------------------------------------------------------------------------------------------------

Write-Host "Script started, will fix permissions for `"$Path`""
$FileCounter = 0
$DirCounter = 0
$ItemsUpdated = 0
$UnsuccesfulUpdates = 0
$OwnerObject = New-Object System.Security.Principal.NTAccount("$env:USERDOMAIN", "$env:USERNAME")
$CurrentUser = "$env:USERDOMAIN\$env:USERNAME"
$TargetUserAccessRuleObjectForFile = New-Object System.Security.AccessControl.FileSystemAccessRule($TargetUser, "FullControl", "Allow")
$CurrentUserAccessRuleObjectForFile = New-Object System.Security.AccessControl.FileSystemAccessRule($CurrentUser, "FullControl", "Allow")
$TargetUserAccessRuleObjectForDir = New-Object System.Security.AccessControl.FileSystemAccessRule($TargetUser, "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
$CurrentUserAccessRuleObjectForDir = New-Object System.Security.AccessControl.FileSystemAccessRule($CurrentUser, "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")

if ($SupportLongPath) { $Path = "\\?\$Path" }

Write-Host "Checking for elevated privileges..."
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
	throw "Script is not running with elevated privileges, exiting. Run your powershell `"As administrator`""
}
Write-Host "[OK]"
Write-Host "Traversing directories recursively..."
Traverse-Directory -PathToProcess $Path
Write-Progress -Activity "Traversing directories recursively" -Completed
Write-Host "Processed total $FileCounter files, $DirCounter dirs. Updated items $($ItemsUpdated - $UnsuccesfulUpdates)/$UnsuccesfulUpdates (success/failure)"
