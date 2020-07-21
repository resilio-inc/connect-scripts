# Win Agent MSI

This folder contains components to embed sync.conf file inside MSI installer. The MSI installer with embedded sync.conf has next differences to one downloaded from Resilio download site:
* allows to embed your sync.conf so you get a single installer file
* Unsigned (Resilio, Inc. digital signature is broken). Please re-sign if necessary

## attach-sync-conf-to-msi.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
The script performs embedding configuration file in the MSI. Script is not signed, and requires certain actions to be able to run in your environment:
* If launching script from Powershell terminal, run `Set-ExecutionPolicy Bypass` command before using script.
* If launching script from Windows command prompt, run `powershell.exe -ExecutionPolicy Bypass -Noprofile -File attach-sync-conf-to-msi.ps1 -MSIPath <path_to_msi> -SyncConfPath <path_to_config>`