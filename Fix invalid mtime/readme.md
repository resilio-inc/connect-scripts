# Fix invalid mtime solition
This folder contains a script intended to go over folders recursively and set modification time (mtime) to current time for all files where mtime is invalid. Mtime considered to be invalid if:
* It is greater than current time (i.e. in future) for more than 1 minute
* It is equal to Epoch zero (i.e. 1970.01.01. 00:00:00)
* It is negative (i.e. created before 1970.01.01. 00:00:00
Note that it may take a while to scan large directories.

## fix-mtime.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
The script goes over directories tree recursively, updating mtime for all files with invalid mtime. 

## Script usage
* Ensure that the user account running script has enough permissions to update files timestamps
* Use "-WhatIf" to see which files are going to be updated without actually updating their timestamps
* Set the "-FilesAmountExpected" to approximate amount of files for more precise progress bar behavior
Sample script start:

```.\fix-mtime.ps1 -Path C:\TestFolders\TestTime\ -SupportLongPath -FilesAmountExpected 20000000 *> c:\temp\files.log```