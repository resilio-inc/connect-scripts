# Additional agents script solution
This folder contains a script intended to run additional agents on the same system or destroy additional agents if no longer need them.

## multi-agent.ps1 ![alt text](https://i.imgur.com/F6NAQyb.png "Script supports standard Get-Help cmdlet")
The script identifies amount of agent running on the system. If the parameter AgentCount greater than actual amount - the script will start additional agents. If it's lesser, the script will terminate extra agents and cleanup their files / folders. The script won't be able to terminate agents installed via MSI (like MC agent or Agent installed via MSI).
The script attempts to behave smart. It detects where the sync.conf stays to create additional sync.confs at the same location. Same with the storage folder and agent names - if some defined in the sync.conf, it will follow the pattern.

### Script usage
* Run script with elevated privileges. 
* Use the -DontStartService switch to prevent agent from starting services after creation.
Sample script start:

```.\multi-agent.ps1 -AgentCount 6```

## multi-agent.sh 
The script intended to run on DEB or RPM linux. It requires Agent package to be installed already as well as requires the presence of `/etc/resilio-agent/sync.conf` file. The script will create a .service template file and has an ability to start/stop a required number of agents as well as enable/disable them for automatic startup. The script ensures agents are using different ports (starting from the port 3841) as well as differen names (in a format of hostname-X).

### Script usage
* Run script as root
* No parameters will display help text
* Run script with the `init` parameter first to create .service file template
* Other commands are `start X`, `stop`, `enable X`, `disable` to respectively start X amount of instances, stop all instances, enable X amount of instances, disable all the instances in systemd

Example script start:
```./multi-agent.sh start 10```