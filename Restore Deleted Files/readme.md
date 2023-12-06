# Restore files from archive solution
This folder contains a script intended to restore DELETED files from archive. It only pulls the files that DO NOT exist outside of the archive. The script can work in 2 modes: 
* scan archive for files there. This way is not reliable if your files OUTSIDE of the archive may look like my_rendered_image.1344.exr as script considers that to be a VERSION of a file, not a standalone file
* scan agent's database for removed files. The most reliable way though it requires agent service to be stopped

## restore-files-advanced.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
Read script's help for full description
The script can run in "WhatIf" mode to only display files to be restored.

## Script usage
### Basic (scan archive) mode
* Run the script and point it to the synced folder
Sample script start:
```restore-files-advanced.ps1 -Path 'c:\TestFolders\FullSync' -WhatIf ```

### Advanced (database) mode
* Open Dump Debug Status for the Agent where you plan to restore files
* Find the job and it's ID (a long sequence like 4E1DB078C81BFB8D4ED16402E946964CE55D8440)
* Find the corresponding database <hash>.db in Agent's storage folder
* Open powershell window with elevated privileges
* Install the PSSQlite module with the command ```Install-Module PSSQlite```, agree to install
* !!! Stop the agent service !!!
* Run the script, point the path to synced folder and the path to database containing 
Sample script start:
```restore-files-advanced.ps1 -Path 'c:\TestFolders\FullSync' -Database 'C:\ProgramData\Resilio\Connect Agent\4E1DB078C81BFB8D4ED16402E946964CE55D8440.35.db' -WhatIf -SearchDB ```