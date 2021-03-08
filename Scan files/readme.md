# Scanning and comparing directories script solution
This folder contains a script intended to scan the folder you synced or plan to sync and create a list of files that should be synced and ones that should be ignored. You can also use this script to compare 2 lists of files to see what was actually synced. As this solution is based on Powershell it only works for Windows OS.

## scan-directory.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
* The script is non-invasive at all and does not do any changes to your dataset.
* It respects deep paths if -SupportLongPath switch is used
* It warns about any permissions or folder content read issues it encounters
* It does NOT support complex ignore filters containing more than 1 component
* It is performance and RAM optimized and capable to deal with large datasets (1M+). Though note that it will take some time due to slow Powershell nature to process larger folders

## Script usage
```.\scan-directory.ps1 -Path F:\MyFolder -OutPath C:\Support -SupportLongPath```

Scans the F:\MyFolder for files that will be synced and that will be ignored. Will respect long paths and save the results in
C:\Support\MyFolder-synced.txt
C:\Support\MyFolder-dot-sync.txt  
C:\Support\MyFolder-ignored.txt   
C:\Support\MyFolder-perms.txt     
respectively. See the outputs help section for details of each file.

```.\scan-directory.ps1 -FileListA C:\Support\MyFolder-synced.txt -FileListB "\\myserver\c$\Support\MyFolder-synced.txt"```

Compares 2 scans on 2 different computer and profives a difference, i.e. files that were not synced for some reason.
