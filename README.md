# connect-scripts
Resilio Connect Scripts is a set of recipes and solutions for commonly done tasks in the Resilio Connect product

## Agent Upgrade Pack
This folder contains scripts and files to upgrade all agents in your setup via the distribution job. See details inside 

## restore_archive.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
This script restores deleted files from archive (.sync\Archive folder of any synchronized folder) or just shows files that were deleted and could be restored.

Note that the script has certain limitation as it considers all the `<filename>.number.<extension>` to be the versions of `<filename>.<extension>` file.

## Mac Agent Package
This folder contains scripts and files to create OS X package with sync.conf pre-packaged to automatically connect to selected Management Console.

## Win Agent MSI
This folder contains scripts and instructions to package sync.conf insider Connect Agent MSI installer to automatically connect to Management Console after installation.

## Move Files Pack
This folder contains solution to clean up files on source peer once they are confirmed to be delivered to destination

## Move Arriving Files (Sync job)
This folder contains solution to move files that get delivered by Sync job our of the arrival folder

## start-process-under-logged-on-user.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
This script allows to start process (`-AppPath`) with arguments (`-AppCmd`) under currently logged on user and show UI for him. Also, you can specify working directory (`-WorkDir`) and wait till process will be ended (`-Wait`).

## api_sample1.ps1
This is an example script for Console API usage. Given a name of the agent (can be masked with wildcards) it checks that agent status in all job runs that are active now.

## deploy_agent_mac.sh
This script allows to register agent of Mac as a LaunchDaemon and run under limited user accout. 

