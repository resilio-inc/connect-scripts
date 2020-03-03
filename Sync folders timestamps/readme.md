# Sync folders timestamps
This folder contains a script which is intended to syncronize folders timestamps (modification time and creation time). 

## sync-foldertime.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
To collect snapshot of folders tree with timestamps run:
`.\sync-foldertime.ps -MakeSnapshot -SourcePath <path_to_directory> -OutFile <snapshot_xml_file_name>`

To apply collected snapshot of timestamps run:
 `.\sync-foldertime.ps1 -ApplyFolderTimes -PathToSnapshot <path_to_xml>' -DestinationPath <path_to_synced_folder>`

Please note that both runs of this script may take a significant time if there are many files and folders in target directory