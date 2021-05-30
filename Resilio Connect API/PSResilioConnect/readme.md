# Management Console PS module
This module is a wrapper to control Resilio Management Console over RESTful API.
## Usage
* Use `Import-Module <path_to_psm1>` call to load module. 
* Once loaded use `Initialize-ResilioMCConnection` to supply module hostname of MC and API Token
* Once done, call `Remove-Module ResilioConnect` to unload the module

## Supported functionality
### Jobs
* Creation / removal
* Start / Stop
* Enumeration / search
* Job details
* Job search by name or ID
* Changing job properties (limited support)
	
### Agents
* Updating tags
* Adding / removing to groups
* Adding / removing to runs
* Enumeration / search
* Agent removal

### Job runs
* Enumeration / search
* Adding / removing agent to job run

### Groups
* Adding / removing agents to group
* Enumeration / search 

### Profiles
* Adding / removing job / agent profiles
* Enumeration / search job / agent profiles 

## Not (yet) supported functionality
* Groups creation / removal
* Adjusting agents priorities within job runs
* Pausing / unpausing job run
* Storages