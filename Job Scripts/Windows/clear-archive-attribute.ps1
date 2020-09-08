# current directory and any sub-directories
$path = ".\"

# look at files that were modified more than 48 hours ago
$cutoffDate = (get-date).addHours(-48).date
$files = Get-ChildItem -Path $path -Recurse | `
		 	Where-Object {!($_.psIsContainer) -AND `
		 	($_.lastwritetime -lt $cutoffDate -AND $_.creationtime -lt $cutoffDate)}

$attribute = [io.fileattributes]::archive

"Script started"
Foreach($file in $files) 
{
	If((Get-ItemProperty -Path $file.fullname).attributes -band $attribute)
	{ 
		"Removing Archive bit from '$file'"
		Set-ItemProperty -Path $file.fullname -Name attributes `
			-Value ((Get-ItemProperty $file.fullname).attributes -BXOR $attribute)
		#"New value of '$file' attributes"
		#(Get-ItemProperty -Path $file.fullname).attributes
	}
	ELSE
	{ 
		#Write-host -ForegroundColor blue `
		#"'$file' does not have the $attribute bit set"
	}
}
"Script done"