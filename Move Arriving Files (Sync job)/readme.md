# Move Arriving Files 

This folder contains recipe to solve following scenario:
* Files appear on peer A and need to be delivered to peer B as soon as they appear
* Once files arrive to peer B, they must be moved to another location
* Once files arrive to peer B they need to get removed from peer A

## Jobs configuration
Create 2 jobs: syncrhonization job and script job

### Synchronization job
Serves for files delivery. While creating job take care of next parameters:
* Both source and destination peers should have "Read-write" permissions.

### Script job
Does post-delivery files processing. Ensure next job configuration:
* The job gets scheduled to run every 10 minutes
* The checkbox "Wait for job run to complete before starting new one" in the scheduler is checked
* The script shell changed to powershell
* Copy the script content from "move-arriving-files.ps1" in this repository
* Adjust the starting parameters of the script according to section below
* Add any additional code to "Marker 1" and "Marker 2" places of the script to adjust its behavior if necesary

## Script parameters
| Parameter | Meaning |
| --------- | ------- |
|`$path_to_observe`| Sets the path to be monitored by script for new arriving files. Leave it as "." if you point the script execution folder to the same folder you specified for destination in Sync job.|
|`$path_to_move_files_to`| Sets the path files get moved to|
|`$exit_counter_seconds`|  Sets the amount of time script keeps running and monitoring for new files. Should be greater or equal to script job schedule for continious files transfer|
|`$step_seconds`| Sets the interval on how often script checks for new files.|
|`$keep_path`| If set to `$true` will retain relative path structure for each file moved. If set to `$false` will drop all files to root folder when moved |
|`$clean_empty_folders`| If set will clean up folders after files were moved away.|