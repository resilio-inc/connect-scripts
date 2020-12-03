# Fix permissions script solution
This folder contains a script intended to go over folders recursively and add the permission for LOCAL SYSTEM (default target user) to grant access for Resilio Agent for all the files and folders inside. This is extremely useful in a situation when many files or folders have inheritance flag disabled so it can't be fixed with Windows built-in tools. The script behaves as non-ivasively as it is possible, though review the changes it may introduce: 
* it will attempt to only fix entries that are missing the target user account "FullAccess"
* It will only take ownership if necessary and return it back when done
* It will remove all the explicit "Deny" entries on the folders if running user account has no enough permissions to list directory content
* It will add "FullAccess" to the folders that return "Permission denied" error when attempting to get listed 


## fix-permissions.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
The script goes over directories tree recursively, assigning "Allow FullControl" permission entry to all items it encounters that have no such permission for selected user account

## Script usage
* Run script under domain admin user account
* Use "-TakeOwnership" switch to deal with extra-prohibited entries. Script will take the ownership temporarily (assign domain admin as the owner) and only then try to insert LOCAL SYSTEM full access entry.
* Set the "-FilesAmountExpected" to approximate amount of files for more precise progress bar behavior
Sample script start:

```.\fix-permissions.ps1 -Path C:\TestFolders\TestPerms\ -SupportLongPath -FilesAmountExpected 20000000 -Verbose 4> c:\temp\perms.log```