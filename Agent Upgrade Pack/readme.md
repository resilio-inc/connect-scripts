# Agent Upgrade Pack

This folder contains set of scripts and components to perform agent upgrade via Distribution job. Upgrade technique implies startup of the scripts via TaskScheduler service to fully detach from original agent performing upgrade. Upgrade is done via moving binaries and storage folder (if necessary).
Upgrade script determines itelf which versions are being upgraded and takes care of stroage migration. Upgrade script detects x64/x86 platform automatically and decides which agent exe to take.
All scripts imply they are running in "C:\ResilioUpgrade" folder and the folder also contains Agent upgradeables (executables Resilio-Connect-Agent.exe and Resilio-Connect-Agent_x64.exe)
Minimal set of files that should be present in C:\ResilioUpgrade to get agents upgraded is:
* agent_upgrade.ps1
* verify_upgrade.ps1
* ResilioUpgrade.xml
* Resilio-Connect-Agent.exe (get from download site)
* Resilio-Connect-Agent_x64.exe (get from download site)

The files *.copy_to_trigger are not necessary to be present in distributed folder but copied to the trigger of upgrade job on MC. See user's upgrade instruction [here](https://connect.resilio.com/hc/en-us/articles/115001080444-Upgrading-your-Agents-using-Distribution-Job).

## agent_upgrade.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
The script is actually doing an upgrade, which includes:
* Stopping the service (and automatically killing it if can't stop for 10 minutes)
* Replacing the binary with a new one
* Migrating storage folder if upgrade is done from pre-2.5 to 2.5 
* Supplying proper permissions for the new storage folder
* Starting the service
The script drops upgrade.log in same directoru it resides.

## verify_upgrade.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
The script verifies if all the pre-requisites are met to perform an upgrade. In case something is missing, script will report an error and exit with error code. In case you cannot get upgrade logs, you can rely on codes:

| Error code    | Error meaning                                                                               |
| ------------- | ------------------------------------------------------------------------------------------- |
| 0             | All is okay, proceed with an upgrade                                                        |
| 1             | Upgrade is not necessary as version of old and new binaries match                           |
| 2             | upgradable x86 binary missing                                                               |
| 3             | upgradable x64 binary missing                                                               |
| 4             | powershell script agent_upgrade.ps1 missing                                                 |
| 5             | Task Scheduler configuration file resilioupgrade.xml missing                                |
| 6             | Upgrade folder is different from "C:\ResilioUpgrade"                                        |
| 12            | Agent runs without elevated privileges, upgrade not possible                                |
| 13            | Laptop is runninng on battery mode, upgrade impossible. Once laptop powered, start job again|
| 14            | task scheduler not running, upgrade not possible                                            |
| 15            | installed version is newer than one supplied, upgrade script stops with no changes          |
| 16            | Agent installation not found (no proper registry key pointing to executable location)       |

If error code is higher than zero, log of the verification is dumped to "verify.log" file next to the script. If you do not plan to deply any x86 machines upgrade, specify `-NoX86exeCheck` switch.

## ResilioUpgrade.xml
This XML contains proper configuration for the task which will run the upgrade script.

## upgrade-post-download.cmd.copy_to_trigger
This file contains cmd script which needs to be placed to post-download trigger of the upgrade job. It is intended to:
* verify that target machine is eligible for the upgrade
* Provide a readable error which can help admin to identify why upgrade cannot be performed
* Launch the upgrade script (agent_upgrade.ps1) via task scheduler service
