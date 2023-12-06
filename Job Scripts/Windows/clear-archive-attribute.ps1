$startTime = (Get-Date)
"Script started"

# current directory and any sub-directories
$path = ".\"

$attribute = [io.fileattributes]::archive

# look at files that were modified more than 48 hours ago
$cutoffDate = (get-date).addHours(-48).date
$files = Get-ChildItem -Path $path -Recurse | `
		 	Where-Object {!($_.psIsContainer) -AND `
		 	($_.lastwritetime -lt $cutoffDate -AND $_.creationtime -lt $cutoffDate) -AND `
			($_.attributes -band $attribute)}

$files_processed = 0

Foreach($file in $files) 
{
	#"Removing Archive bit from '$file'"
	$files_processed++
	Set-ItemProperty -Path $file.fullname -Name attributes `
		-Value ((Get-ItemProperty $file.fullname).attributes -BXOR $attribute)
	#"New value of '$file' attributes"
	#(Get-ItemProperty -Path $file.fullname).attributes
}

$endTime = (Get-Date)

"Processed '$files_processed' files."
"Processing took '$($endTime - $startTime)'"
"Script done"