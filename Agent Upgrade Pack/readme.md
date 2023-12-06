# Agent Upgrade Pack

This folder contains set of scripts to perform agent upgrade via Distribution job. Upgrade technique implies startup of the scripts via TaskScheduler service to fully detach from original agent performing upgrade. Upgrade is done via moving binaries and storage folder (if necessary) as well as updating explorer extension DLLs.
Upgrade script determines itelf which versions are being upgraded and takes care of stroage migration. Upgrade script detects x64/x86 platform automatically and decides which agent exe to take.
The scripts are directory-agnostic and can be started from any folder.
Minimal set of files that should be present in your upgrade folder to get agents upgraded is:
* agent_upgrade.ps1
* Resilio-Connect-Agent.exe (get from download site, not mandatory if no x86 windows to upgrade)
* Resilio-Connect-Agent_x64.exe (get from download site)

The files *.copy_to_trigger are not necessary to be present in distributed folder but copied to the trigger of upgrade job on MC. See user's upgrade instruction [here](https://connect.resilio.com/hc/en-us/articles/360004845800-Updating-your-Agents-using-Distribution-Job).

## agent_upgrade.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
The script is actually doing an upgrade, which includes:
* Verification of upgrade pre-requisites
* Installation of Task Scheduler task which performs the upgrade
* Stopping the service (and automatically killing it if can't stop for 10 minutes)
* Replacing the binary with a new one
* Migrating storage folder if upgrade is done from pre-2.5 to 2.5+
* Supplying proper permissions for the new storage folder
* Starting the service
* Updating Explorer extensions to the new one (with explorer automatic restart)

During verification step the script verifies if all the pre-requisites are met to perform an upgrade. In case something is missing, script will report an error and exit with error code. In case you cannot get upgrade logs, you can rely on codes:
<a id="error-table"></a>
| Error code    | Error meaning                                                                               |
| ------------- | ------------------------------------------------------------------------------------------- |
| 0             | All is okay, proceed with an upgrade                                                        |
| 1             | Upgrade is not necessary as version of old and new binaries match                           |
| 2             | upgradable x86 binary missing                                                               |
| 3             | upgradable x64 binary missing                                                               |
| 4             | powershell script agent_upgrade.ps1 missing                                                 |
| 12            | Agent runs without elevated privileges, upgrade not possible                                |
| 13            | Laptop is runninng on battery mode, upgrade impossible. Once laptop powered, start job again|
| 14            | task scheduler not running, upgrade not possible                                            |
| 15            | installed version is newer than one supplied, upgrade script stops with no changes          |
| 16            | Agent installation not found (no proper registry key pointing to executable location)       |
| 17            | Powershell version is below 4.0, automatic upgrade is not possible                          |
| 18            | agent_upgrade.ps1 file is damaged (actually, it is HTML page, not a PS script)              |
| 19            | Disk space with storage folder is insufficient for the upgrade                              |

If you don't see your error code in the table above, update your Agent Upgrade Pack.
If error code is higher than zero, log of the verification is dumped to "verify.log" file next to the script. 
If you do not plan to deploy any x86 machines upgrade, specify `-NoX86exeCheck` switch in the call `agent_upgrade.ps1 ... -Verify`.
If you do not want to verify the disk space before the upgrade, specify `-NoDiskSpaceCheck` switch in the call `agent_upgrade.ps1 ... -Verify`.
If you do not plan to upgrade explorer extensions, specify `-NoExtensionUpgrade` switch in the call `agent_upgrade.ps1 ... -CreateUpgradeTask`.

During the upgrade step the script drops upgrade.log in same directory it resides.

## upgrade-post-download.cmd.copy_to_trigger
This file contains cmd script which needs to be placed to post-download trigger of the upgrade job. It is intended to:
* verify that target machine is eligible for the upgrade
* Provide a readable error which can help admin to identify why upgrade cannot be performed
* Launch the upgrade script (agent_upgrade.ps1) via task scheduler service
