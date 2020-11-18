# Toromont script solution
This folder contains a script for Toromont intended to go over folders recursively and add the permission for LOCAL SYSTEM to access all the files and folders inside. They have many items that have permissions inheritence disabled and therefore cannot be accessed by Agent.


## fix-permissions.ps1
The script goes over directories tree recursively, assigning "Allow FullControl" permission entry to all items it encounters 
that have no such permission for selected user account

## Script usage
* Run script under domain admin user account
* Use "-TakeOwnership" switch to deal with extra-prohibited entries. Script will take the ownership of the time (assign domain admin as the owner) and only then try to insert LOCAL SYSTEM full access entry.
* Set the "-FilesAmountExpected" to approximate amount of files for more precise progress bar behavior