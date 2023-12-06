# Additional agents script solution
This folder contains a script intended to run additional agents on the same system or destroy additional agents if no longer need them.

## multi-agent.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
The script identifies amount of agent running on the system. If the parameter AgentCount greater than actual amount - the script will start additional agents. If it's lesser, the script will terminate extra agents and cleanup their files / folders. The script won't be able to terminate agents installed via MSI (like MC agent or Agent installed via MSI).
The script attempts to behave smart. It detects where the sync.conf stays to create additional sync.confs at the same location. Same with the storage folder and agent names - if some defined in the sync.conf, it will follow the pattern.

## Script usage
* Run script with elevated privileges. 
* Use the -DontStartService switch to prevent agent from starting services after creation.
Sample script start:

```.\multi-agent.ps1 -AgentCount 6```