
function ConvertFrom-UnixTime
{
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[long]$unxtime,
		[switch]$MilliSec
	)
	if ($MilliSec) { $unxtime = $unxtime/1000 }
	$res = (Get-Date 01.01.1970) + ([System.TimeSpan]::fromseconds($unxtime))
	return $res
}
# --------------------------------------------------------------------------------------------------------------------------------

function ConvertTo-UnixTime
{
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[datetime]$time,
		[switch]$MilliSec
	)
	$res = [long]((New-TimeSpan -Start (Get-Date "01/01/1970") -End $time).TotalSeconds)
	if ($MilliSec) { $res = $res*1000 }
	return $res
}
# --------------------------------------------------------------------------------------------------------------------------------

function Initialize-ConnectJobBlob
{
	<#
	.SYNOPSIS
	Call this function to start a Resilio Connect job creation / update
	.DESCRIPTION
	This function prepares a blob object which represents all properties for the upcoming job creation or update. New call will wipe out
	all the properties already loaded into blob object.
	All consequent call of Add-*ToBlob keep adding data until you call New-ConnectJobFromBlob or Update-ConnectJobFromBlob function which actually creates / updates
	Resilio Connect job based on accumulated data.
	.PARAMETER Name
	Job name. Can be any. Can be later used to automatically create paths for agents or groups participating in the job.
	.PARAMETER JobType
	Specifies type of a job.
	.PARAMETER Description	
	Description of a job. Optional.
	.PARAMETER ProfileID
	ID of the job profile to use. Leave empty to use default job profile.
	.PARAMETER Priority
	Priority to assign to a job
	.LINK
	https://connect.resilio.com/hc/en-us/articles/115001080024-Synchronization-job
	https://connect.resilio.com/hc/en-us/articles/115001070190-Distribution-job
	https://connect.resilio.com/hc/en-us/articles/115001070170-Consolidation-Job
	https://connect.resilio.com/hc/en-us/articles/115001080544-Script-job
	#>
	param
	(
		[string]$Name,
		[ValidateSet("sync", "script", "distribution", "consolidation")]
		[string]$JobType,
		[string]$Description,
		[int]$ProfileID,
		[int]$Priority
	)
	$script:cjblob = New-Object System.Object
	if ($Name) { $script:cjblob | Add-Member -NotePropertyName "name" -NotePropertyValue $Name }
	if ($JobType) { $script:cjblob | Add-Member -NotePropertyName "type" -NotePropertyValue $JobType }
	if ($Description) { $script:cjblob | Add-Member -NotePropertyName "description" -NotePropertyValue $Description }
	if ($ProfileID) { $script:cjblob | Add-Member -NotePropertyName "profile_id" -NotePropertyValue $ProfileID }
	if ($Priority)
	{
		$tmp = New-Object System.Object
		$tmp | Add-Member -NotePropertyName "priority" -NotePropertyValue $Priority
		$script:cjblob | Add-Member -NotePropertyName "settings" -NotePropertyValue $tmp
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Add-GroupToBlob
{
	<#
	.SYNOPSIS
	Adds group with paths to send / receive data to job object.
	.DESCRIPTION
	Call this function if you want to add a group of agents in the upcoming job creation. Note, that Initialize-ConnectJobBlob must be called
	before you call this function. 
	This function can be called multiple times for adding more groups.
	.PARAMETER GroupID
	Identified of a group to add. Can be piped from Find-Groups call.
	.PARAMETER Macro
	Specified path Macro for the group inside this job. Can take values of %FOLDERS_STORAGE%", "%HOME%", "%USERPROFILE%", "%DOWNLOADS%"
	.PARAMETER WinPath
	Specifies path for Windows machines in the group. If Macro specified, the path must be relative.
	.PARAMETER OsxPath
	Specifies path for OS X machines in the group. If Macro specified, the path must be relative.
	.PARAMETER LinuxPath
	Specifies path for Linux machines in the group. If Macro specified, the path must be relative.
	.PARAMETER AutoPath
	Forces to set up all paths automatically equal to job name
	.PARAMETER Permission
	Specifies access level of that group to the data. Can be "rw, ro, srw, sro". s* values represent selective sync and are only applicable
	to Sync job type. For distribution and consolidation jobs rw represents source and ro represents destination.
	.LINK
	https://connect.resilio.com/hc/en-us/articles/115001069970-Path-Macros
	#>
	param
	(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$GroupID,
		[string]$Macro = "",
		[string]$WinPath = "",
		[string]$OsxPath = "",
		[string]$LinuxPath = "",
		[switch]$AutoPath,
		[ValidateSet("ro", "rw", "sro", "srw")]
		[Parameter(Mandatory = $true)]
		[string]$Permission
	)
	BEGIN
	{
		if ($AutoPath)
		{
			$WinPath = $script:cjblob.name
			$OsxPath = $script:cjblob.name
			$LinuxPath = $script:cjblob.name
		}
	}
	PROCESS
	{
		$group = New-Object System.Object
		$group | Add-Member -NotePropertyName "id" -NotePropertyValue $GroupID
		$group | Add-Member -NotePropertyName "permission" -NotePropertyValue $Permission
		$resiliopath = New-Object System.Object
		if (![System.String]::IsNullOrEmpty($Macro)) { $resiliopath | Add-Member -NotePropertyName "macro" -NotePropertyValue $Macro }
		$resiliopath | Add-Member -NotePropertyName "win" -NotePropertyValue $WinPath
		$resiliopath | Add-Member -NotePropertyName "osx" -NotePropertyValue $OsxPath
		$resiliopath | Add-Member -NotePropertyName "linux" -NotePropertyValue $LinuxPath
		$group | Add-Member -NotePropertyName "path" -NotePropertyValue $resiliopath
		if (!$script:cjblob.groups)
		{
			$groups = @()
			$groups += $group
			$script:cjblob | Add-Member -NotePropertyName "groups" -NotePropertyValue $groups
		}
		else { $script:cjblob.groups += $group }
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Add-AgentToBlob
{
	<#
	.SYNOPSIS
	Adds agent with paths to send / receive data to job object.
	.DESCRIPTION
	Call this function if you want to add an agent in the upcoming job creation. Note, that Initialize-ConnectJobBlob must be called
	before you call this function. 
	This function can be called multiple times for adding more agents.
	.PARAMETER AgentID
	Identifies an agent to add. Can be piped from Find-Agents call.
	.PARAMETER Macro
	Specified path Macro for the agent inside this job. Can take values of %FOLDERS_STORAGE%", "%HOME%", "%USERPROFILE%", "%DOWNLOADS%"
	.PARAMETER WinPath
	Specifies path for the agent if it is Windows machine. If Macro specified, the path must be relative.
	.PARAMETER OsxPath
	Specifies path for the agent if it is OS X machine. If Macro specified, the path must be relative.
	.PARAMETER LinuxPath
	Specifies path for the agent if it is Linux machine. If Macro specified, the path must be relative.
	.PARAMETER AutoPath
	Forces to set up all paths automatically equal to job name
	.PARAMETER Permission
	Specifies access level of that agent to the data. Can be "rw, ro, srw, sro". s* values represent selective sync and are only applicable
	to Sync job type. For distribution and consolidation jobs rw represents source and ro represents destination.
	.LINK
	https://connect.resilio.com/hc/en-us/articles/115001069970-Path-Macros
	#>
	param
	(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$AgentID,
		[string]$Macro = "",
		[string]$WinPath = "",
		[string]$OsxPath = "",
		[string]$LinuxPath = "",
		[switch]$AutoPath,
		[ValidateSet("ro", "rw", "sro", "srw")]
		[Parameter(Mandatory = $true)]
		[string]$Permission
	)
	BEGIN
	{
		if ($AutoPath)
		{
			$WinPath = $script:cjblob.name
			$OsxPath = $script:cjblob.name
			$LinuxPath = $script:cjblob.name
		}
	}
	PROCESS
	{
		$agent = New-Object System.Object
		$agent | Add-Member -NotePropertyName "id" -NotePropertyValue $AgentID
		$agent | Add-Member -NotePropertyName "permission" -NotePropertyValue $Permission
		$resiliopath = New-Object System.Object
		if (![System.String]::IsNullOrEmpty($Macro)) { $resiliopath | Add-Member -NotePropertyName "macro" -NotePropertyValue $Macro }		
		$resiliopath | Add-Member -NotePropertyName "win" -NotePropertyValue $WinPath
		$resiliopath | Add-Member -NotePropertyName "osx" -NotePropertyValue $OsxPath
		$resiliopath | Add-Member -NotePropertyName "linux" -NotePropertyValue $LinuxPath
		$agent | Add-Member -NotePropertyName "path" -NotePropertyValue $resiliopath
		if (!$script:cjblob.agents)
		{
			$agents = @()
			$agents += $agent
			$script:cjblob | Add-Member -NotePropertyName "agents" -NotePropertyValue $agents
		}
		else { $script:cjblob.agents += $agent }
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Add-ScriptToBlob
{
	<#
	.SYNOPSIS
	Adds triggers to the distribution and consolidation job or script to the script job.
	.DESCRIPTION
	Call this function if you want to add a trigger to the distribution or consolidation job. Also use it if you need to set a script for the scrip job.
	Note, that Initialize-ConnectJobBlob must be called before you call this function. Function	pushes required script inside the job object, 
	which is used later in New-ConnectJobFromBlob call.
	Function can be called multiple times to add scripts for different operating systems or different trigger conditions.
	.PARAMETER OS
	Specified which OS the script you are adding is targeted for.
	.PARAMETER ScriptBody
	Script itself. Can be multi-line string.
	.PARAMETER ShellPath.
	Path to the shell to execute script. Don't specify for standard shell.
	.PARAMETER ScriptFileExtension
	Extension for the script temp file. Don't specify for standard shell.
	.PARAMETER ScriptType
	Set this parameter to "scriptjob" if the script you are adding is a script for script job. Set to "pre_indexing", "post_download" or "complete" if
	the script is actually a trigger for distribution or consolidation job.
	.PARAMETER Powershell
	Set this switch if your script is a powershell script for Windows. This will automatically set proper values for ShellPath and ScriptFileExtension
	#>
	param
	(
		[ValidateSet("linux", "win", "osx")]
		[Parameter(Mandatory = $true)]
		[string]$OS,
		[Parameter(Mandatory = $true)]
		[string]$ScriptBody,
		[string]$ShellPath,
		[string]$ScriptFileExtension,
		[ValidateSet("pre_indexing", "post_download", "complete", "scriptjob")]
		[Parameter(Mandatory = $true)]
		[string]$ScriptType,
		[switch]$PowerShell
	)
	if ($PowerShell -and $OS -eq "win")
	{
		$ShellPath = "powershell -NoProfile -ExecutionPolicy Bypass -NonInteractive -InputFormat None -File"
		$ScriptFileExtension = "ps1"
	}
	$scriptprops = New-Object System.Object
	$scriptprops | Add-Member -NotePropertyName "script" -NotePropertyValue "$ScriptBody"
	if (![System.String]::IsNullOrEmpty($ShellPath)) { $scriptprops | Add-Member -NotePropertyName "shell" -NotePropertyValue "$ShellPath" }
	if (![System.String]::IsNullOrEmpty($ScriptFileExtension)) { $scriptprops | Add-Member -NotePropertyName "ext" -NotePropertyValue "$ScriptFileExtension" }
	
	if ($ScriptType -eq "scriptjob") # Add script for scripjob here
	{
		if (!$script:cjblob.script)
		{
			$scriptobj = New-Object System.Object
			$script:cjblob | Add-Member -NotePropertyName "script" -NotePropertyValue $scriptobj
		}
		$script:cjblob.script | Add-Member -NotePropertyName $OS -NotePropertyValue $scriptprops -Force
		return
	}
	
	# If this is not a scripjob, add it to proper "triggers" section
	
	if (!$script:cjblob.triggers)
	{
		$scriptobj = New-Object System.Object
		$script:cjblob | Add-Member -NotePropertyName "triggers" -NotePropertyValue $scriptobj
	}
	if (!$script:cjblob.triggers."$ScriptType")
	{
		$scriptobj = New-Object System.Object
		$script:cjblob.triggers | Add-Member -NotePropertyName "$ScriptType" -NotePropertyValue $scriptobj
	}
	$script:cjblob.triggers."$ScriptType" | Add-Member -NotePropertyName $OS -NotePropertyValue $scriptprops -Force
	
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Add-SchedulerToBlob
{
	<#
	.SYNOPSIS
	Use this function to add scheduler to the object representing job
	.DESCRIPTION
	This function allows set up scheduler in the object representing job. Scheduler can be very flexible therefore there are many ways to run this function. 
	Every run discards previous scheduler from the job object and replaces it with a new one. Note, that Initialize-ConnectJobBlob must be called before you 
	call this function.
	Actual scheduler type depends on the parameters you use call it with.
	.PARAMETER EveryXMinutes
	Creates a scheduler to run job every X amount of minutes.
	.PARAMETER EveryXHours
	Creates a scheduler to run job every X amount of hours.
	.PARAMETER EveryXDays
	Creates a scheduler to run job every X amount of days. Must be used together with EveryXDaysAt to specify job run time.
	.PARAMETER EveryXDaysAt
	Specifies a time to run a job. Must be used together with EveryXDays to specify period of job startup.
	.PARAMETER WeeklyOnDays
	Creates a scheduler to run job on selected days of the week. Must be used together with WeeklyAtTimes. This parameter must be an array of integer, where
	each number represents a day of week starting from zero representing Sunday, one representing Monday, etc.
	.PARAMETER WeeklyAtTimes
	Specifies a time to run job. Must be used together with WeeklyOnDays. This parameter must be array of DateTime (or strings convertable to DateTime) where
	each entry represents a time to start a job on a day chosen with WeeklyOnDays.
	.PARAMETER StartOn
	Optional. Specifies a time when scheduler becomes active. 
	.PARAMETER StopOn
	Optional. Specifies a time when scheduler stops working. 
	.PARAMETER SkipIfRunning
	Set parameter to prevent scheduler re-starting the job when a new time to start comes and the previous run is still going.
	.EXAMPLE
	Add-SchedulerToBlob -EveryXDays 10 -EveryXDaysAt "10:00"
	Sets up scheduler to run job every 10 days at 10:00
	.EXAMPLE
	Add-SchedulerToBlob -EveryXMinutes 30 -StartOn "2019-09-16" -StopOn "2019-09-30 23:59"
	Sets up scheduler to run job every 30 minutes, effective from Sep 16 2019 to end of
	September same year
	.EXAMPLE
	Add-SchedulerToBlob -OnceAt "2019-09-17 15:13"
	Sets up scheduler to run job only once on 2019-09-17 at 15:13
	.EXAMPLE
	Add-SchedulerToBlob -WeeklyOnDays (0, 2, 3) -WeeklyAtTimes ("9:00", "15:00") -SkipIfRunning
	Sets up scheduler to run job every Sunday, Tuesday, Wednesdat at 9:00 and 15:00 and also
	not to spawn new job run if previous one is still going
	.LINK
	https://connect.resilio.com/hc/en-us/articles/115001070190-Distribution-job
	https://connect.resilio.com/hc/en-us/articles/115001070170-Consolidation-Job
	https://connect.resilio.com/hc/en-us/articles/115001080544-Script-job
	#>
	param
	(
		[Parameter(ParameterSetName = "EveryXMinutes")]
		[int]$EveryXMinutes,
		[Parameter(ParameterSetName = "EveryXHours")]
		[int]$EveryXHours,
		[Parameter(ParameterSetName = "EveryXDays")]
		[int]$EveryXDays,
		[Parameter(ParameterSetName = "EveryXDays")]
		[datetime]$EveryXDaysAt,
		[Parameter(ParameterSetName = "OnceAt")]
		[datetime]$OnceAt,
		[Parameter(ParameterSetName = "Weekly")]
		[array]$WeeklyOnDays,
		[Parameter(ParameterSetName = "Weekly")]
		[array]$WeeklyAtTimes,
		[Parameter(ParameterSetName = "EveryXMinutes")]
		[Parameter(ParameterSetName = "EveryXHours")]
		[Parameter(ParameterSetName = "EveryXDays")]
		[Parameter(ParameterSetName = "Weekly")]
		[datetime]$StartOn,
		[Parameter(ParameterSetName = "EveryXMinutes")]
		[Parameter(ParameterSetName = "EveryXHours")]
		[Parameter(ParameterSetName = "EveryXDays")]
		[Parameter(ParameterSetName = "Weekly")]
		[datetime]$StopOn,
		[Parameter(ParameterSetName = "EveryXMinutes")]
		[Parameter(ParameterSetName = "EveryXHours")]
		[Parameter(ParameterSetName = "EveryXDays")]
		[Parameter(ParameterSetName = "Weekly")]
		[switch]$SkipIfRunning
	)
	$schdobj = New-Object System.Object
	if ($SkipIfRunning) { $schdobj | Add-Member -NotePropertyName "skip_if_running" -NotePropertyValue $true }
	if ($StartOn) { $schdobj | Add-Member -NotePropertyName "start" -NotePropertyValue (ConvertTo-UnixTime $StartOn) }
	if ($StopOn) { $schdobj | Add-Member -NotePropertyName "finish" -NotePropertyValue (ConvertTo-UnixTime $StopOn) }
	if ($EveryXMinutes)
	{
		$schdobj | Add-Member -NotePropertyName "type" -NotePropertyValue "minutes"
		$schdobj | Add-Member -NotePropertyName "every" -NotePropertyValue $EveryXMinutes
		$script:cjblob | Add-Member -NotePropertyName "scheduler" -NotePropertyValue $schdobj -Force
		return
	}
	if ($EveryXHours)
	{
		$schdobj | Add-Member -NotePropertyName "type" -NotePropertyValue "hourly"
		$schdobj | Add-Member -NotePropertyName "every" -NotePropertyValue $EveryXHours
		$script:cjblob | Add-Member -NotePropertyName "scheduler" -NotePropertyValue $schdobj -Force
		return
	}
	if ($EveryXDays)
	{
		$datesec = $EveryXDaysAt.Hour*3600 + $EveryXDaysAt.Minute*60 + $EveryXDaysAt.Second
		$schdobj | Add-Member -NotePropertyName "type" -NotePropertyValue "daily"
		$schdobj | Add-Member -NotePropertyName "every" -NotePropertyValue $EveryXDays
		$schdobj | Add-Member -NotePropertyName "time" -NotePropertyValue $datesec
		$script:cjblob | Add-Member -NotePropertyName "scheduler" -NotePropertyValue $schdobj -Force
		return
	}
	if ($OnceAt)
	{
		$schdobj | Add-Member -NotePropertyName "type" -NotePropertyValue "once"
		$schdobj | Add-Member -NotePropertyName "time" -NotePropertyValue ConvertTo-UnixTime($OnceAt)
		$script:cjblob | Add-Member -NotePropertyName "scheduler" -NotePropertyValue $schdobj -Force
		return
	}
	if ($WeeklyOnDays)
	{
		$timesArray = @()
		foreach ($TimeStr in $WeeklyAtTimes)
		{
			$Time = [datetime]$TimeStr
			$TimeInSec = $Time.Hour * 3600 + $Time.Minute * 60 + $Time.Second
			$timesArray += $TimeInSec
		}
		$schdobj | Add-Member -NotePropertyName "type" -NotePropertyValue "weekly"
		$schdobj | Add-Member -NotePropertyName "days" -NotePropertyValue $WeeklyOnDays
		$schdobj | Add-Member -NotePropertyName "time" -NotePropertyValue $timesArray
		$script:cjblob | Add-Member -NotePropertyName "scheduler" -NotePropertyValue $schdobj -Force
		return
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function New-ConnectJobFromBlob
{
	<#
	.SYNOPSIS
	Call this function to create new job. Ensure to initilize and push necessary data to a blob.
	.DESCRIPTION
	This function is intended to create a new Resilio Connect job. Before calling this function ensure to 
	also call: 
	- InitializeConnectJobBlob to give job a name and type
	- AddAgentToBlob or AddGroupToBlob to assign some agents to the job
	.EXAMPLE
	PS> Initialize-ConnectJobBlob -Name "_Cadabra Test" -JobType "distribution"
	PS> Add-AgentToBlob -AgentID 145 -WinPath "C:\MyTestData" -Permission rw
	PS> Add-GroupToBlob -GroupID 8 -Macro "%DOWNLOADS%" -AutoPath -Permission ro
	PS> Add-SchedulerToBlob -EveryXMinutes 30 -StartOn "2019-09-16" -StopOn "2019-09-30 23:59"
	PS> New-ConnectJobFromBlob
	
	This set of calls will cause Management Console to create a new job with Agent 145 as a source,
	Group with ID 8 as a destination
	
	.LINK
	https://www.resilio.com/api/documentation/#api-Jobs-CreateJob
	#>
	$json = ($script:cjblob | ConvertTo-Json -Depth 10)
	Invoke-ConnectFunction -Method POST -RestPath "jobs" -JSON $json
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function New-Profile
{
	<#
	.SYNOPSIS
	Creates new job or agent profile
	.DESCRIPTION
	Call the function to create new job or agent profile. Specify multiple parameters with Settings parameter feeding Poweshell hashtable. Function creates agent profile if type is not specified
	.PARAMETER Name
	Specifies new name for the profile.
	.PARAMETER Description
	Specifies new description for the profile. Optional. 
	.PARAMETER Setting
	Specifies a hashtable of settings to be part of the profile.
	.PARAMETER Type
	Specifies if function adjusts agent or job profile. 
	.EXAMPLE
	New-Profile -Name "My profile" -Type agent -Settings @{ rate_limit_local_peers = $true; "folder_defaults.known_hosts" = "192.168.1.15:3839;192.168.1.18:3839" }
	Create new agent profile which forces to limit bandwidth in LAN and defines couple of known hosts
	.LINK
	https://www.resilio.com/api/documentation/#api-Profiles-CreateAgentProfile
	.LINK
	https://www.resilio.com/api/documentation/#api-Profiles-CreateJobProfile
	.LINK
	https://connect.resilio.com/hc/en-us/articles/360003750320-Profiles
	#>
	[CmdletBinding()]
	param (
		[ValidateSet("agent", "job")]
		[string]$Type = "agent",
		[Parameter(Mandatory = $true)]
		[string]$Name,
		[string]$Description,
		[hashtable]$Settings
	)
	PROCESS
	{
		$profileobj = New-Object System.Object
		if ($Name) { $profileobj | Add-Member -NotePropertyName "name" -NotePropertyValue $Name }
		if ($Description) { $profileobj | Add-Member -NotePropertyName "description" -NotePropertyValue $Description }
		if ($Settings) { $profileobj | Add-Member -NotePropertyName "settings" -NotePropertyValue $Settings }
		$prepared_json = $profileobj | ConvertTo-Json -Depth 10
		if ($Type -eq "agent") { $path = "agent_profiles" }
		else { $path = "job_profiles" }
		Invoke-ConnectFunction -Method POST -RestPath "/$path" -JSON $prepared_json
	}
	
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Remove-AgentFromJobRun
{
	<#
	.SYNOPSIS
	Function intended to remove agent(s) from ongoing job runs
	.DESCRIPTION
	Use the function to remove agent(s) from ongoing job runs
 	.PARAMETER JobRunID
	Set to specify which job run you want to modify
	.PARAMETER AgentID
	Specify AgentID to remove from job run. This parameter can be piped and accept multiple agent IDs
	.LINK
	https://www.resilio.com/api/documentation/#api-Runs-StopRunOnAgents
	#>
	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[int]$JobRunID,
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$AgentID
	)
	BEGIN 
	{
		$agentlist = @()
	}
	PROCESS
	{
	     $agentlist += $AgentID
	}
	END
	{
		$json = ConvertTo-Json $agentlist
		Invoke-ConnectFunction -Method PUT -RestPath "runs/$JobRunID/agents/stop" -JSON $json
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Add-AgentToJobRun
{
	<#
	.SYNOPSIS
	Function intended to add agent(s) to ongoing job runs
	.DESCRIPTION
	Use the function to add agent(s) to ongoing job runs
 	.PARAMETER JobRunID
	Set to specify which job run you want agents to join
	.PARAMETER AgentID
	Set as a single int or array of ints (if you want to add many
	agents) to specify which agents you want to run to the job run. 
	.PARAMETER Macro
	Specify macro preceding the path for job data
	.PARAMETER WinPath 
	Specify path for windows machines being added to the job run
	.PARAMETER OSXPath
	Specify path for OS X machines being added to the job run
	.PARAMETER LinuxPath 
	Specify path for Linux machines being added to the job run
	.OUTPUTS
	The function returns OK or throws exception
	#>
	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[int]$JobRunID,
		[Parameter(Mandatory = $true, ValueFromPipeline=$true)]
		[int]$AgentID,
		[string]$Macro = "",
		[string]$WinPath = "",
		[string]$OsxPath = "",
		[string]$LinuxPath = "",
		[switch]$AutoPath
	)
	BEGIN 
	{
		$JobRun = Find-ConnectJobRuns -JobRunID $JobRunID -ActiveOnly -ReturnObject
		if ($AutoPath)
		{
			$WinPath = $JobRun.name
			$OsxPath = $JobRun.name
			$LinuxPath = $JobRun.name
		}
		
		if (!$JobRun) { throw "Job run with ID $JobRunID not found" }
		$jsonobj = @()
		$runs = 0
	}
	PROCESS
	{
		$agentobj = New-Object System.Object
		$agentobj | Add-Member -NotePropertyName "id" -NotePropertyValue $AgentID
		$pathobj = New-Object System.Object
		if ($Macro) { $pathobj | Add-Member -NotePropertyName "macro" -NotePropertyValue $macro }
		$pathobj | Add-Member -NotePropertyName "win" -NotePropertyValue $winpath
		$pathobj | Add-Member -NotePropertyName "osx" -NotePropertyValue $osxpath
		$pathobj | Add-Member -NotePropertyName "linux" -NotePropertyValue $linuxpath
		$agentobj | Add-Member -NotePropertyName "path" -NotePropertyValue $pathobj
		$jsonobj += $agentobj
		$runs++
	}
	END
	{
		$json = $jsonobj | ConvertTo-Json
		if ($runs -eq 1) { $json = "[$json]" }
		Invoke-ConnectFunction -Method POST -RestPath "runs/$JobRunID/agents" -JSON $json
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Invoke-ConnectFunction
{
	<#
	.SYNOPSIS
	Function intended to call a generic rest function of MC
	.DESCRIPTION
	Use the function to call any other non-implemented function of
	MC Console API
	.PARAMETER RestPath
	Specifies route for the API call (appended to base_url specified
	in Initialize-ResilioMCConnection
	.PARAMETER Method
	Specify the REST method
	.PARAMETER JSON
	Specify JSON of the content (or leave empty if none)
	.OUTPUTS
	The function returns the body of message returned by MC server
	#>
	[CmdletBinding()]
	param (
		[string]$RestPath,
		[string]$Method,
		[string]$JSON
	)
	try
	{
		if ($PSVersionTable.PSVersion -lt "6.0")
		{
			if (!$JSON) { $response = Invoke-RestMethod -Method $Method -uri "$base_url/$RestPath" -Headers @{ "Authorization" = "Token $API_token" } -ContentType "Application/json" }
			else
			{
				$response = Invoke-RestMethod -Method $Method -uri "$base_url/$RestPath" -Headers @{ "Authorization" = "Token $API_token" } -ContentType "Application/json" -Body:$JSON
				Write-Debug "Sending JSON: $JSON"
			}
		}
		else
		{
			if (!$JSON) { $response = Invoke-RestMethod -Method $Method -uri "$base_url/$RestPath" -Headers @{ "Authorization" = "Token $API_token" } -ContentType "Application/json" -SkipCertificateCheck }
			else
			{
				$response = Invoke-RestMethod -Method $Method -uri "$base_url/$RestPath" -Headers @{ "Authorization" = "Token $API_token" } -ContentType "Application/json" -Body:$JSON -SkipCertificateCheck
				Write-Debug "Sending JSON: $JSON"
			}
		}
	}
	catch [System.Net.WebException]
	{
		Write-Debug "WebException fulltext is: $_"
		
		if ($_.Exception.Response.StatusCode.value__)
		{
			$errortext = "Error code: $($_.Exception.Response.StatusCode.value__)"
			$result = $_.Exception.Response.GetResponseStream()
			$reader = New-Object System.IO.StreamReader($result)
			$reader.BaseStream.Position = 0
			$reader.DiscardBufferedData()
			$responseBody = $reader.ReadToEnd();
			$errortext = "$errortext ; Response body is: $responseBody"
			$errorcat = "InvalidData"
			$response = $responseBody
		}
		else
		{
			$errortext = $_
			$errorcat = "ConnectionError"
		}
		#$PSCmdlet.WriteError($errortext) #to reset a $? var to false
		Write-Error -Message $errortext -Category $errorcat -TargetObject $_
		#return $responseBody
		#throw $_
	}
	catch
	{
		throw "Some unknown error happened while performing REST request"
	}
	
	return $response
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Find-ConnectJobRuns
{
	<#
	.SYNOPSIS
	Function intended to get list of job runs matching the filter
	.DESCRIPTION
	Use the function to get list of job run IDs or job run objects matching the 
	job id or job name
	.PARAMETER JobID
	Specifies id of the job to filter our job runs
	.PARAMETER JobName
	Specifies the job name to filter our job runs
	.PARAMETER OnlyOne
	Will force to throw exception if more than one job run matches the filter.
	.PARAMETER ActiveOnly
	Forces to only find ongoing job runs
	.PARAMETER ReturnObject
	Forces function to return job run object(s) instead of id(s)
	.OUTPUTS
	The funtion will throw exception if fails by any reason. Otherwise returns 
	an array of job IDs. 
	.LINK
	https://www.resilio.com/api/documentation/#api-Runs-GetRuns
	#>
	
	[CmdletBinding()]
	param (
		[Parameter(ParameterSetName = "ByJobID", Mandatory = $true)]
		[Parameter(ParameterSetName = "ByJobRunID")]
		[Parameter(ParameterSetName = "ByName")]
		[int]$JobID = -1,
		[SupportsWildcards()]
		[Parameter(ParameterSetName = "ByJobID")]
		[Parameter(ParameterSetName = "ByJobRunID")]
		[Parameter(ParameterSetName = "ByName", Mandatory = $true)]
		[string]$JobName,
		[Parameter(ParameterSetName = "ByJobID")]
		[Parameter(ParameterSetName = "ByJobRunID", Mandatory = $true)]
		[Parameter(ParameterSetName = "ByName")]
		[int]$JobRunID = -1,
		[switch]$OnlyOne,
		[switch]$ActiveOnly,
		[switch]$ReturnObject
	)
	
	if ($JobRunID -ne -1)
	{
		$units = Invoke-ConnectFunction -Method GET -RestPath "runs/$JobRunID"
		if ($ActiveOnly -and $units.status -ne 'working') { $units = @() }
		return $units
	}
	
	$units = Get-ConnectJobRuns
	if ($JobID -eq -1)
	{
		$searchfield = "name"
		$searchvalue = $JobName
	}
	else
	{
		$searchfield = "job_id"
		$searchvalue = $JobID
	}
	
	if ($ActiveOnly)
	{
		$matching_jobruns = Find-ConnectObjects -ObjectList $units -FieldName $searchfield -FieldValue $searchvalue -ReturnObject
		return Find-ConnectObjects -ObjectList $matching_jobruns -FieldName "active" -FieldValue "True" -OnlyOne:$OnlyOne -ReturnObject:$ReturnObject
	}
	else
	{
		return Find-ConnectObjects -ObjectList $units -FieldName $searchfield -FieldValue $searchvalue -OnlyOne:$OnlyOne -ReturnObject:$ReturnObject
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Get-ConnectJobRuns
{
	[CmdletBinding()]
	param ()
	
	$offset = 0
	$pagelimit = 500
	$jobruns = @()
	$jobrunspage = Invoke-ConnectFunction -Method GET -RestPath "runs?offset=$offset&limit=$pagelimit"
	while ($jobrunspage.data.length -gt 0)
	{
		$jobruns += $jobrunspage.data
		$offset += $pagelimit
		$jobrunspage = Invoke-ConnectFunction -Method GET -RestPath "runs?offset=$offset&limit=$pagelimit"
	}
	return $jobruns
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Get-Profiles
{
	<#
	.SYNOPSIS
	Function intended to return a list of all agent or job profiles
	.DESCRIPTION
	Call this function to get full list of agent or job profiles. Use Type parameter to specify if you need to get agent or job profiles
	.PARAMETER Type
	Specifies type of the profile - agent or job
	.LINK
	https://www.resilio.com/api/documentation/#api-Profiles-GetAgentProfiles
	.LINK
	https://www.resilio.com/api/documentation/#api-Profiles-GetJobProfiles
	#>
	[CmdletBinding()]
	param (
	[ValidateNotNullOrEmpty()]
	[ValidateSet("agent", "job")]
	[string]$Type = "agent"
	)
	
	if ($Type -eq "agent") { $path = "agent_profiles" }
	else { $path = "job_profiles" }
	return Invoke-ConnectFunction -Method GET -RestPath "$path"
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Get-Agents
{
	<#
	.SYNOPSIS
	Function intended to return a list of agents
	.DESCRIPTION
	Use the function to get full list of Agents Management Console knows of. 
	.OUTPUTS
	The funtion will throw exception if fails by any reason, or the object
	if succeeds
	.LINK
	https://www.resilio.com/api/documentation/#api-Agents-GetAgents
	#>
	[CmdletBinding()]
	param ()
	return Invoke-ConnectFunction -Method GET -RestPath "agents"
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Get-Groups
{
	<#
	.SYNOPSIS
	Function intended to return a list of groups
	.DESCRIPTION
	Use the function to get full list of Groups Management Console knows of. 
	.OUTPUTS
	The funtion will throw exception if fails by any reason, or the object
	if succeeds
	.LINK
	https://www.resilio.com/api/documentation/#api-Groups-GetGroups
	#>
	
	[CmdletBinding()]
	param ()
	
	return Invoke-ConnectFunction -Method GET -RestPath "groups"
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Get-ConnectJobs
{
	<#
	.SYNOPSIS
	Function intended to return a list of jobs
	.DESCRIPTION
	Use the function to get full list of jobs Management Console knows of. 
	.OUTPUTS
	The funtion will throw exception if fails by any reason, or the object
	if succeeds
	.LINK
	https://www.resilio.com/api/documentation/#api-Groups-GetGroups
	#>
	[CmdletBinding()]
	param ()
	
	return Invoke-ConnectFunction -Method GET -RestPath "jobs"
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Set-AgentsToGroup
{
	<#
	.SYNOPSIS
	Function intended to assign a list of agents to a group
	.DESCRIPTION
	Use the function to set a new list of agents to the group. New list overwrites
	the existing one
	.PARAMETER GroupID
	GroupID specifies the ID of a group to be changed
	.PARAMETER AgentsID
	AgentsID can be single agent ID or array of agents IDs to be assigned to 
	a group.
	.OUTPUTS
	The funtion will throw exception if fails by any reason, or exit if succeeds.
	.LINK
	https://www.resilio.com/api/documentation/#api-Groups-UpdateGroup
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[int]$GroupID,
		[Parameter(Mandatory = $true)]
		$AgentsID
	)
	
	$agentslist = @()
	foreach ($agent_id in $AgentsID)
	{
		$item = "`{`"id`":$agent_id`}"
		$agentslist += $item
	}
	
	$json = "{`"agents`":[$($agentslist -join ",")]}"
	
	Invoke-ConnectFunction -Method PUT -RestPath "groups/$GroupID" -JSON $json
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Remove-AgentTag
{
	<#
	.SYNOPSIS
	Function remove specified tag from one or many agents
	.DESCRIPTION
	Use this function to remove agent's tag. If the tag does not exist, it simply exists
	.PARAMETER AgentID
	Specify an agent ID or an array of agent IDs to get tag added to
	.PARAMETER Name
	Specify tag name. Only use latin and underscore symbols
	.LINK
	https://connect.resilio.com/hc/en-us/articles/115001069730-Using-Agent-Tags
	.LINK
	https://www.resilio.com/api/documentation/#api-Agents-UpdateAgent
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$AgentID,
		[Parameter(Mandatory = $true)]
		[string]$Name
	)
	PROCESS
	{
		$agenttags = (Find-Agents -AgentID $AgentID).tags
		$foundtags = $agenttags | Where-Object name -EQ $Name
		if ($foundtags)
		{
			$agenttags = $agenttags | Where-Object {$_.name -ne $Name}
			$json = $agenttags | ConvertTo-Json
			$json = "{`"tags`":$json}"
			Invoke-ConnectFunction -Method PUT -RestPath "agents/$AgentID" -JSON $json
		}
	}	
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Add-AgentTag
{
	<#
	.SYNOPSIS
	Function adds specified tag + value pair to one or many agents
	.DESCRIPTION
	Use this function to update agent's tags. If tag already exists, it just
	updates the value. If it does not exit, then it's added. Function can
	be called with array of agent IDs to add a tag to many agents with a
	single call.
	.PARAMETER AgentID
	Specify an agent ID or an array of agent IDs to get tag added to
	.PARAMETER Name
	Specify tag name. Only use latin and underscore symbols
	.PARAMETER Value
	Specify new / updated tag value.
	.LINK
	https://connect.resilio.com/hc/en-us/articles/115001069730-Using-Agent-Tags
	.LINK
	https://www.resilio.com/api/documentation/#api-Agents-UpdateAgent
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$AgentID,
		[Parameter(Mandatory = $true)]
		[string]$Name,
		[string]$Value
	)
	PROCESS
	{
		$agenttags = (Find-Agents -AgentID $AgentID).tags
		$foundtags = $agenttags | Where-Object name -EQ $Name
		if ($foundtags)
		{
			$foundtags.value = $Value
		}
		else
		{
			$tmp = New-Object System.Object
			$tmp | Add-Member -NotePropertyName "name" -NotePropertyValue $Name
			$tmp | Add-Member -NotePropertyName "value" -NotePropertyValue $Value
			$agenttags += $tmp
		}
		$json = $agenttags | ConvertTo-Json
		$json = "{`"tags`":$json}"
		Invoke-ConnectFunction -Method PUT -RestPath "agents/$AgentID" -JSON $json
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Add-AgentToGroup
{
	<#
	.SYNOPSIS
	Function intended to add a list of agents to a group
	.DESCRIPTION
	Use the function to add new agent(s) to the group. New list adds to the agents
	already in the group
	.PARAMETER GroupID
	GroupID specifies the ID of a group to be changed
	.PARAMETER AgentID
	AgentsID can be single agent ID or array of agents IDs to be assigned to 
	a group.
	.OUTPUTS
	The funtion will throw exception if fails by any reason, or exit if succeeds.
	.LINK
	https://www.resilio.com/api/documentation/#api-Groups-UpdateGroup
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[int]$GroupID,
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		$AgentID
	)
	BEGIN 
	{
		$group = Find-Groups -GroupID $GroupID
		$agentslist = @()
		foreach ($agent_id in $group.agents)
		{
			$item = "`{`"id`":$($agent_id.id)`}"
			$agentslist += $item
		}
	}
	PROCESS
	{
		$item = "`{`"id`":$AgentID`}"
		$agentslist += $item
	}
	END
	{
		$json = "{`"agents`":[$($agentslist -join ",")]}"
		
		Invoke-ConnectFunction -Method PUT -RestPath "groups/$GroupID" -JSON $json
	}	
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Remove-AgentFromGroup
{
	<#
	.SYNOPSIS
	Function intended to remove a list of agents from the group
	.DESCRIPTION
	Use the function to remove agents from the group. The absense of the agent
	in a group will not cause an error.
	.PARAMETER GroupID
	GroupID specifies the ID of a group to be changed
	.PARAMETER AgentID
	AgentsID can be single agent ID or array of agents IDs to be removed from 
	the group.
	.OUTPUTS
	The funtion will throw exception if fails by any reason, or exit if succeeds.
	.LINK
	https://www.resilio.com/api/documentation/#api-Groups-UpdateGroup
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[int]$GroupID,
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$AgentID
	)
	BEGIN 
	{
		$group = Find-Groups -GroupID $GroupID
		
		$agentslist = New-Object System.Collections.ArrayList
		$agentsstringlist = @()
		foreach ($agent_id in $group.agents) #Build the arraylist of existing agents
		{
			$agentslist.Add($agent_id.id)
		}
	}
	PROCESS
	{
		$agentslist.Remove($AgentID) # Then remove all of the necessray agents from there
	}
	END
	{
		foreach ($agent_id in $agentslist) #build a list to be merged in a single json
		{
			$item = "`{`"id`":$($agent_id)`}"
			$agentsstringlist += $item
		}
		
		$json = "{`"agents`":[$($agentsstringlist -join ",")]}"
		Invoke-ConnectFunction -Method PUT -RestPath "groups/$GroupID" -JSON $json
	}
	
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Find-ConnectObjects # got used to be internal function
{
	param (
		[Parameter(ValueFromPipeline = $true)]
		$ObjectList,
		[string]$FieldName='name',
		[string]$FieldValue,
		[switch]$ReturnObject,
		[switch]$OnlyOne
	)
	$matching_units = @()
	foreach ($unit in $ObjectList)
	{
		if ($unit."$FieldName" -like $FieldValue)
		{
			if ($ReturnObject) { $matching_units += $unit }
			else { $matching_units += $unit.id }
		}
	}
	if ($OnlyOne.IsPresent)
	{
		if ($matching_units.Length -eq 0) { throw "No objects found, must be one" }
		if ($matching_units.Length -gt 1) { throw "Several objects found, must be one" }
		return $matching_units[0]
	}
	return $matching_units
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Find-Groups
{
	<#
	.SYNOPSIS
	Function intended to get list of groups matching the GroupName filter
	.DESCRIPTION
	Use the function to get list of group ids matching the GroupName parameter
	.PARAMETER GroupName
	Specifies the filter for groups to be found. Ignored if GroupID is specified.
	.PARAMETER GroupID
	Specifies ID of the group to be found
	.PARAMETER OnlyOne
	Will force to throw exception if more than one group matches the filter.
	.OUTPUTS
	The function will throw exception if fails by any reason. Otherwise returns 
	an array of group IDs. 
	.EXAMPLE
	(Find-Groups -GroupName "LocalAgents*" -OnlyOne -ReturnObject).agents.id.contains(111)
	Checks if the group named LocalAgents contain the agent with id 111. Will fail if there multiple groups starting with LocalAgents string.
	.LINK
	https://www.resilio.com/api/documentation/#api-Groups-GetGroups
	#>
	[CmdletBinding()]
	param (
		[SupportsWildcards()]
		[string]$GroupName,
		[int]$GroupID = -1,
		[switch]$OnlyOne,
		[switch]$ReturnObject
	)
	if ($GroupID -eq -1)
	{
		$units = Get-Groups	
		return Find-ConnectObjects -ObjectList $units -FieldValue $GroupName -OnlyOne:$OnlyOne -ReturnObject:$ReturnObject
	}
	else
	{
		return Invoke-ConnectFunction -Method GET -RestPath "groups/$GroupID"
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------
function Find-Profiles
{
	<#
	.SYNOPSIS
	Get agent or job profile by name or ID
	.DESCRIPTION
	Function intended to get a profile by ID or find all profiles matching name filter
	.PARAMETER Name
	Specifies the filter for agent or job profiles to be found. Parameter ignored if ID specified.
	.PARAMETER ID
	Specifies the profile ID to be found
	.PARAMETER OnlyOne
	Will force to throw exception if more than one profile matches the filter.
	.PARAMETER ReturnObject
	Will force function to return an array of objects instead of array of profile IDs matchine the filter
	.PARAMETER Type
	Specifies type of the profile to find - job or agent
	.OUTPUTS
	If profile requested by ID, returns profile object
	If profile requested by name filter, returns an array or IDs unless ReturnObject switch supplied.
	.LINK
	https://www.resilio.com/api/documentation/#api-Profiles-GetJobProfiles
	.LINK
	https://www.resilio.com/api/documentation/#api-Profiles-GetAgentProfiles
	#>
	[CmdletBinding()]
	param (
		[SupportsWildcards()]
		[string]$Name,
		[int]$ID = -1,
		[ValidateSet("agent", "job")]
		[string]$Type = "agent",
		[switch]$OnlyOne,
		[switch]$ReturnObject
	)
	if ($ID -eq -1)
	{
		$units = Get-Profiles -Type:$Type
		return Find-ConnectObjects -ObjectList $units -FieldValue $Name -OnlyOne:$OnlyOne -ReturnObject:$ReturnObject
	}
	else
	{
		if ($Type -eq "agent") { $path = "agent_profiles" }
		else { $path = "job_profiles" }
		return Invoke-ConnectFunction -Method GET -RestPath "$path/$ID"
	}	
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Find-Agents
{
	<#
	.SYNOPSIS
	Function intended to get list of agents by search criteria
	.DESCRIPTION
	Use the function to get list of agent IDs or agent objects by different search criteria: by name, agent ID or by job run ID
	.PARAMETER AgentName
	Specifies the filter for agents to be found. Parameter ignored if AgentID specified.
	.PARAMETER AgentID
	Specifies the Agent ID to be found
	.PARAMETER JobRunID
	Specifies job run ID and forces function to find all agents participating in that job run with their statuses.
	.PARAMETER OnlyOne
	Will force to throw exception if more than one agent matches the filter.
	.OUTPUTS
	The funtion will throw exception if fails by any reason. Otherwise returns 
	an array of agent IDs. 
	.LINK
	https://www.resilio.com/api/documentation/#api-Agents-GetAgents
	#>
	[CmdletBinding()]
	param (
		[SupportsWildcards()]
		[string]$AgentName,
		[int]$AgentID = -1,
		[switch]$OnlyOne,
		[switch]$ReturnObject,
		[int]$JobRunID
	)
	if ($AgentID -ne -1) # Search by Agent ID
	{
		return Invoke-ConnectFunction -Method GET -RestPath "agents/$AgentID"
	}
	if ($JobRunID) # Get all agents from particular job run
	{
		return (Invoke-ConnectFunction -Method GET -RestPath "runs/$JobRunID/agents").data
	}
	
	# Get agents by name
	$units = Get-Agents
	return Find-ConnectObjects -ObjectList $units -FieldValue $AgentName -OnlyOne:$OnlyOne -ReturnObject:$ReturnObject
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Find-ConnectJobs
{
	<#
	.SYNOPSIS
	Function intended to get list of jobs matching the name filter
	.DESCRIPTION
	Use the function to get list of job IDs matching the AgentName parameter
	.PARAMETER JobName
	Specifies the filter for agents to be found
	.PARAMETER OnlyOne
	Will force to throw exception if more than one job matches the filter.
	.EXAMPLE
	Find-ConnectJobs -JobName "Schematics transfer*" | Start-ConnectJob
	Starts all the jobs starting with the name "Schematics transfer*"
	.OUTPUTS
	The funtion will throw exception if fails by any reason. Otherwise returns 
	an array of job IDs. 
	.LINK
	https://www.resilio.com/api/documentation/#api-Agents-GetAgents
	#>
	[CmdletBinding()]
	param (
		[SupportsWildcards()]
		[string]$JobName,
		[int]$JobID = -1,
		[switch]$OnlyOne,
		[switch]$ReturnObject
	)
	
	if ($JobID -ne -1)
	{
		return Invoke-ConnectFunction -Method GET -RestPath "jobs/$JobID"
	}
	
	$units = Get-ConnectJobs
	return Find-ConnectObjects -ObjectList $units -FieldValue $JobName -OnlyOne:$OnlyOne -ReturnObject:$ReturnObject
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Start-ConnectJob
{
	<#
	.SYNOPSIS
	Function intended to start job(s)
	.DESCRIPTION
	Use the function to start job by ID or by name. When name is used, it can start single job or multiple ones
	.PARAMETER JobID
	Specifies the ID of a job to be started. Can be piped for multiple jobs. If you need to start job by name, use Find-ConnectJobs and pipe output to this command.
	.PARAMETER Agents
	Optional parameter. Allows to run job only on selected agent(s)
	.OUTPUTS
	The funtion will throw exception if fails by any reason. No return value.
	.LINK
	https://www.resilio.com/api/documentation/#api-Runs-CreateRun
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$JobID,
		[array]$AgentID
	)
	PROCESS
	{
		if ($AgentID)
		{
			$agentslist = $AgentID -Join ','
			$JSON = "{`"job_id`": $JobID,`"agents`": [$agentslist]}"
		}
		else { $JSON = "{`"job_id`": $JobID}" }
		Invoke-ConnectFunction -Method POST -RestPath "/runs" -JSON $JSON
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Stop-ConnectJob
{
	<#
	.SYNOPSIS
	Function intended to stop job or multiple jobs
	.DESCRIPTION
	Use the function to stop job by ID. Use Find-ConnectJobs and piping to stop multiple jobs
	.PARAMETER JobID
	Specifies the ID of a job to be stopped
	.EXAMPLE
	Find-ConnectJobs -JobName "Ongoing transfer" | Stop-ConnectJob
	Stops job with the aforementioned name
	.EXAMPLE
	Stop-ConnectJob -JobID 115
	Stops job with ID 115
	.OUTPUTS
	The funtion will throw exception if fails by any reason. No return value.
	.LINK
	https://www.resilio.com/api/documentation/#api-Runs-StopRun
	#>
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline = $true)]
		[int]$JobID
	)
	BEGIN 
	{
		$activeruns = Find-ConnectJobRuns -JobName "*" -ActiveOnly -ReturnObject
	}
	PROCESS
	{
		$myrun = $activeruns | Where-Object job_id -EQ $JobID
		if ($myrun)
		{
			Invoke-ConnectFunction -Method PUT -RestPath "runs/$($myrun.id)/stop"
		}
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Remove-Profile
{
	<#
	.SYNOPSIS
	Function intended to return a list of all agent or job profiles
	.DESCRIPTION
	Call this function to get full list of agent or job profiles
	.PARAMETER Type
	Specifies type of the profile - agent or job
	.LINK
	https://www.resilio.com/api/documentation/#api-Profiles-GetAgentProfiles
	.LINK
	https://www.resilio.com/api/documentation/#api-Profiles-GetJobProfiles
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$ID,
		[ValidateSet("agent", "job")]
		[string]$Type = "agent"
	)
	
	BEGIN
	{
		if ($Type -eq "agent") { $path = "agent_profiles" }
		else { $path = "job_profiles" }
	}
	PROCESS
	{
		Invoke-ConnectFunction -Method DELETE -RestPath "$path/$ID"
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Remove-ConnectJob
{
	<#
	.SYNOPSIS
	Function intended to delete job(s)
	.DESCRIPTION
	Use the function to remove one or many jobs by job ID. Accepts piped input for multiple jobs
	.PARAMETER JobID
	Specifies the ID of a job to be removed. Can be piped for multiple jobs
	.OUTPUTS
	The funtion will throw exception if fails by any reason. No return value.
	.LINK
	https://www.resilio.com/api/documentation/#api-Jobs-DeleteJob
	.EXAMPLE
	Find-ConnectJobs -JobName "Test*" | Remove-ConnectJob
	Will cause to delete all jobs starting from "Test..."
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$JobID
	)
	PROCESS
	{
		Invoke-ConnectFunction -Method DELETE -RestPath "/jobs/$JobID"
	}
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Remove-Agent
{
	<#
	.SYNOPSIS
	Removes Agent from Management Console
	.DESCRIPTION
	Forces Management Console to "forget" the agent. Note, that agent will attempt to reconnect using its bootstrap token and might appear again.
	.PARAMETER AgentID
	Specify Agent ID. Pipe multiple IDs if there are many.
	.LINK
	https://www.resilio.com/api/documentation/#api-Agents-DeleteAgent
	#>
	param
	(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$AgentID
	)
	PROCESS
	{
		Invoke-ConnectFunction -Method DELETE -RestPath "agents/$AgentID"
	}
}
# --------------------------------------------------------------------------------------------------------------------------------

function Update-Profile
{
	<#
	.SYNOPSIS
	Changes agent or job profile
	.DESCRIPTION
	Call the function to change a profile Name, Description or any setting. Pipe IDs to update many profiles with one call
	.PARAMETER ID
	Specifies profile ID
	.PARAMETER NewName
	Specifies new name for the profile. Optional.
	.PARAMETER NewDescription
	Specifies new description for the profile. Optional. 
	.PARAMETER Setting
	Specifies a hashtable of settings to apply
	.PARAMETER Type
	Specifies if function adjusts agent or job profile. 
	.EXAMPLE
	Update-Profile -Type agent -id 14 -Settings @{ transfer_job_skip_locked_files = $true; "net.udp_ipv4_mtu" = 1100 }
	Updates agent profile with ID 14 setting transfer_job_skip_locked_files to true and MTU for UDP over IPv4 to 1100 bytes.
	.LINK
	https://www.resilio.com/api/documentation/#api-Profiles-UpdateAgentProfile
	.LINK
	https://www.resilio.com/api/documentation/#api-Profiles-GetJobProfiles
	.LINK
	https://connect.resilio.com/hc/en-us/articles/360003750320-Profiles
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline)]
		[int]$ID,
		[ValidateSet("agent", "job")]
		[string]$Type = "agent",
		[string]$NewName,
		[string]$NewDescription,
		[hashtable]$Settings
	)
	PROCESS
	{
		$profileobj = New-Object System.Object
		if ($NewName) { $profileobj | Add-Member -NotePropertyName "name" -NotePropertyValue $NewName }
		if ($NewDescription) { $profileobj | Add-Member -NotePropertyName "description" -NotePropertyValue $NewDescription }
		if ($Settings) { $profileobj | Add-Member -NotePropertyName "settings" -NotePropertyValue $Settings }
		$prepared_json = $profileobj | ConvertTo-Json -Depth 10
		if ($Type -eq "agent") { $path = "agent_profiles" }
		else { $path = "job_profiles" }
		Invoke-ConnectFunction -Method PUT -RestPath "/$path/$ID" -JSON $prepared_json
	}
}
# --------------------------------------------------------------------------------------------------------------------------------

function Update-ConnectJobFromBlob
{
	<#
	.SYNOPSIS
	Call this function to update a job. Ensure to initilize and push necessary data to a blob.
	.DESCRIPTION
	This function is intended to update existing Resilio Connect job. Before calling this function ensure to call at least: 
	- InitializeConnectJobBlob to create a blob representing a job + call any other functions to adjust groups, scheduler, etc.
	.PARAMETER JobID
	Specify Job ID to get updated
	.EXAMPLE
	PS> Initialize-ConnectJobBlob -Description "I updated that job via API!"
	PS> Add-SchedulerToBlob -EveryXMinutes 30 -StartOn "2019-09-16" -StopOn "2019-09-30 23:59"
	PS> Update-ConnectJobFromBlob
	
	This will change the description of the job and set it a scheduler
	
	.LINK
	https://www.resilio.com/api/documentation/#api-Jobs-UpdateJob
	#>
	param
	(
		[parameter(Mandatory = $true)]
		[int]$JobID
	)
	$json = ($script:cjblob | ConvertTo-Json -Depth 10)
	Invoke-ConnectFunction -Method PUT -RestPath "jobs/$JobID" -JSON $json
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Get-Notifications
{
	<#
	.SYNOPSIS
	Function intended to return a list of all notificaions
	.DESCRIPTION
	Use the function to get full list of all notifications registered in Management Console
	.OUTPUTS
	The funtion will throw exception if fails by any reason, or the array of objects if succeeds
	.LINK
	https://www.resilio.com/api/connect/documentation/#api-Notifications-GetNotifications
	#>
	[CmdletBinding()]
	param ()
	return Invoke-ConnectFunction -Method GET -RestPath "notifications"
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function New-Notification
{
	<#
	.SYNOPSIS
	Function intended to create a new notification
	.DESCRIPTION
	Use this function to create any notification in Management Console. Please note that notification type parameter determines which parameter can be used.
	.PARAMETER SubscriberUsers
	Specify user's ID or array of user IDs to subscribe them to notification(s). You can find user ID in your Management Console, see Settings, Users,
	right-click on the table header and make "ID" visible
	.OUTPUTS
	The funtion will throw exception if fails by any reason, or return the notification object if succeeds
	.EXAMPLE
	New-Notification -Type overview_notification -DailyAt "16:30" -SubscriberUsers 4
	Subscribes user with ID 4 to daily summary at 16:30 
	.EXAMPLE
	New-Notification -Type overview_notification -WeeklyAt "16:30" -SubscriberWebhooks 2 -SubscriberEmails @("test@resilio.com", "test123@resilio.com")
	Subscribes "test@resilio.com", "test123@resilio.com" and webhook with ID 2 to summary, weekly on 16:30
	.EXAMPLE
	New-Notification -Type event_notification -Event added_agent -SubscriberWebhooks 2
	Subscribes webhook with ID 2 to event of new agent added to Management Console
	.EXAMPLE
	New-Notification -Type job_notification -SubscriberEmails "test@resilio.com" -Trigger JOB_RUN_FINISHED -DontSendIfNoDataTransfered
	Subscribes "test@resilio.com" to all jobs finish event. Won't send a notification if no data was transferred
	.EXAMPLE 
	New-Notification -Type job_notification -SubscriberEmails "test@resilio.com" -Trigger JOB_RUN_ERROR -ErrorNotResolvedAfter 3600
	Notify for any job, any error, if not resolved after 1 hour
	.EXAMPLE
	New-Notification -Type job_notification -SubscriberEmails "test@resilio.com" -Trigger JOB_RUN_NOT_COMPLETE -JobNotCompleteAfter 3600
	Notify "test@resilio.com" if any job does not finish within 1 hour
	.EXAMPLE
	New-Notification -Type job_notification -SubscriberEmails "test@resilio.com" -Trigger JOB_RUN_FAILED -JobID 122
	Notify if job with ID 122 finished with errors.
	.LINK
	https://www.resilio.com/api/connect/documentation/#api-Notifications-CreateNotification
	.LINK
	https://connect.resilio.com/hc/en-us/articles/360011054180
	#>
	[CmdletBinding()]
	param (
		[ValidateNotNullOrEmpty()]
		[Parameter(Mandatory = $true)]
		[ValidateSet("job_notification", "event_notification", "overview_notification")]
		[Parameter(ParameterSetName = "JobNotification")]
		[Parameter(ParameterSetName = "EventNotification")]
		[Parameter(ParameterSetName = "OverviewNotification")]
		[string]$Type,
		[Parameter(ParameterSetName = "JobNotification")]
		[Parameter(ParameterSetName = "EventNotification")]
		[Parameter(ParameterSetName = "OverviewNotification")]
		$SubscriberEmails,
		[Parameter(ParameterSetName = "JobNotification")]
		[Parameter(ParameterSetName = "EventNotification")]
		[Parameter(ParameterSetName = "OverviewNotification")]
		$SubscriberWebhooks,
		[Parameter(ParameterSetName = "JobNotification")]
		[Parameter(ParameterSetName = "EventNotification")]
		[Parameter(ParameterSetName = "OverviewNotification")]
		$SubscriberUsers,
		[Parameter(ValueFromPipeline = $true)]
		[Parameter(ParameterSetName = "JobNotification")]
		[Parameter(ParameterSetName = "EventNotification")]
		[Parameter(ParameterSetName = "OverviewNotification")]
		[int]$JobID,
		[ValidateSet("JOB_RUN_FINISHED", "JOB_RUN_FAILED", "JOB_RUN_NOT_COMPLETE", "JOB_RUN_ERROR")]
		[Parameter(ParameterSetName = "JobNotification")]
		[string]$Trigger,
		[Parameter(ParameterSetName = "JobNotification")]
		[string]$ErrorCode,
		[Parameter(ParameterSetName = "JobNotification")]
		[int]$ErrorNotResolvedAfter,
		[Parameter(ParameterSetName = "JobNotification")]
		[switch]$NotifyOnErrorRemove,
		[Parameter(ParameterSetName = "JobNotification")]
		[int]$JobNotCompleteAfter,
		[Parameter(ParameterSetName = "JobNotification")]
		[switch]$DontSendIfNoDataTransfered,
		[Parameter(ParameterSetName = "OverviewNotification")]
		[datetime]$DailyAt,
		[Parameter(ParameterSetName = "OverviewNotification")]
		[datetime]$WeeklyAt,
		[Parameter(ParameterSetName = "EventNotification")]
		[ValidateSet("added_agent", "deleted_agent", "agent_pending_approval")]
		[string]$Event
	)
	PROCESS
	{
		$tmp = New-Object System.Object
		$tmp | Add-Member -NotePropertyName "type" -NotePropertyValue $Type
		$receivers = @()
		foreach ($subscriber in $SubscriberEmails) { $receivers += @{ "email" = $subscriber } }
		foreach ($subscriber in $SubscriberWebhooks) { $receivers += @{ "web_hook_id" = $subscriber } }
		foreach ($subscriber in $SubscriberUsers) { $receivers += @{ "user_id" = $subscriber } }
		$tmp | Add-Member -NotePropertyName "destinations" -NotePropertyValue $receivers
		
		if ($Type -eq "job_notification")
		{
			if ($JobID) { $tmp | Add-Member -NotePropertyName "job_id" -NotePropertyValue $JobID }
			else { $tmp | Add-Member -NotePropertyName "job_id" -NotePropertyValue $null }
			
			$tmp | Add-Member -NotePropertyName "trigger" -NotePropertyValue $Trigger
			
			$settings = New-Object System.Object
			$used_settings = $false
			if ($Trigger -eq "JOB_RUN_FAILED")
			{
				#$settings | Add-Member -NotePropertyName "error_code" -NotePropertyValue $null
				$used_settings = $true
			}
			if ($Trigger -eq "JOB_RUN_ERROR")
			{
				if ($ErrorCode) { $settings | Add-Member -NotePropertyName "error_code" -NotePropertyValue $ErrorCode }
				else { $settings | Add-Member -NotePropertyName "error_code" -NotePropertyValue $null }
				if ($NotifyOnErrorRemove) { $settings | Add-Member -NotePropertyName "notify_on_error_remove" -NotePropertyValue $true }
				else { $settings | Add-Member -NotePropertyName "notify_on_error_remove" -NotePropertyValue $false }
				$used_settings = $true
			}
			if ($NotifyOnErrorRemove) { $settings | Add-Member -NotePropertyName "notify_on_error_remove" -NotePropertyValue $true }
			if ($ErrorNotResolvedAfter)
			{
				$settings | Add-Member -NotePropertyName "notify_after_error_timeout" -NotePropertyValue $true
				$settings | Add-Member -NotePropertyName "error_timeout" -NotePropertyValue $ErrorNotResolvedAfter
				$used_settings = $true
			}
			if ($JobNotCompleteAfter) { $settings | Add-Member -NotePropertyName "complete_timeout" -NotePropertyValue $JobNotCompleteAfter; $used_settings = $true }
			if ($DontSendIfNoDataTransfered) { $settings | Add-Member -NotePropertyName "dont_send_if_no_data_transferred" -NotePropertyValue $true; $used_settings = $true }
			
			if ($used_settings)
			{
				$tmp | Add-Member -NotePropertyName "settings" -NotePropertyValue $settings
			}
		}
		
		if ($Type -eq "overview_notification")
		{
			$settings = New-Object System.Object
			if ($DailyAt)
			{
				$settings | Add-Member -NotePropertyName "daily" -NotePropertyValue $true
				$settings | Add-Member -NotePropertyName "send_time_daily" -NotePropertyValue ($DailyAt.TimeOfDay.TotalSeconds)
			}
			else { $settings | Add-Member -NotePropertyName "daily" -NotePropertyValue $false }
			if ($WeeklyAt)
			{
				$settings | Add-Member -NotePropertyName "weekly" -NotePropertyValue $true
				$settings | Add-Member -NotePropertyName "send_time_weekly" -NotePropertyValue ($WeeklyAt.TimeOfDay.TotalSeconds)
			}
			else { $settings | Add-Member -NotePropertyName "weekly" -NotePropertyValue $false }
			$tmp | Add-Member -NotePropertyName "settings" -NotePropertyValue $settings
		}
		
		if ($Type -eq "event_notification")
		{
			$TextEvent = switch ($Event)
			{
				"added_agent" { 'Added Agent' }
				"deleted_agent" { 'Deleted Agent' }
				"agent_pending_approval" { 'Agent pending approval' }
				default { 'Unknown' }
			}
			$settings = New-Object System.Object
			$settings | Add-Member -NotePropertyName "event" -NotePropertyValue $TextEvent
			$tmp | Add-Member -NotePropertyName "settings" -NotePropertyValue $settings
		}
		$json = ($tmp | ConvertTo-Json -Depth 10)
		Write-Host $json
		Invoke-ConnectFunction -Method POST -RestPath "notifications" -JSON $json
	}
	
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Find-Notifications
{
	<#
	.SYNOPSIS
	Function intended to get notification by its ID
	.DESCRIPTION
	Use the function to get notification by its ID
	.PARAMETER NotificationID
	Specifies the Notification ID to be found
	.OUTPUTS
	The funtion will throw exception if fails by any reason. Otherwise returns a notification object
	.LINK
	https://www.resilio.com/api/connect/documentation/#api-Notifications-GetNotification
	#>
	[CmdletBinding()]
	param (
		[int]$NotificationID
	)
	return Invoke-ConnectFunction -Method GET -RestPath "notifications/$NotificationID"
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Remove-Notification
{
	<#
	.SYNOPSIS
	Function intended to delete notification(s)
	.DESCRIPTION
	Use the function to remove one or many notifications by Notification ID. Accepts piped input for multiple notifications
	.PARAMETER $NotificationID
	Specifies the ID of a notification to be removed. Can be piped for multiple notifications/
	.OUTPUTS
	The funtion will throw exception if fails by any reason. No return value.
	.LINK
	https://www.resilio.com/api/connect/documentation/#api-Notifications-DeleteNotification
	.EXAMPLE
	Remove-Notification -NotificationID 4
	Will cause to delete notification with ID 4
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[int]$NotificationID
	)
	PROCESS
	{
		Invoke-ConnectFunction -Method DELETE -RestPath "/notifications/$JobID"
	}
	
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

function Initialize-ResilioMCConnection
{
	<#
	.SYNOPSIS
	Function configures connection to Management Console over API
	.DESCRIPTION
	Use the function to specify connection properties for Management Console. The function does not actually do any REST calls, just saves the settings in 
	current runspace. Call this function once before calling any other API functions
	.PARAMETER Host
	Specifies hostname (or IP) and port separated by colon
	.PARAMETER Token
	Specifies the API token to be used when making API calls. Token must be
	generated in API section of Management Console.
	.LINK
	https://www.resilio.com/api/documentation/#api-Jobs-UpdateJob
	.EXAMPLE
	Initialize-ResilioMCConnection -Host 127.0.0.1:8443 -Token QQXQ5NGUNBJU3KFMD7SOD6AMRFAG6H2J
	This call tells module to connect to API via localhost, port 8443
	.EXAMPLE
	PS C:\>Initialize-ResilioMCConnection -Host MyFancyServer.mycompany.org:8443 -Token QQXQ5NGUNBJU3KFMD7SOD6AMRFAG6H2J
	PS C:\>$myAgents = Get-Agents
	Connect to API via MyFancyServer.mycompany.org DNS name, port 8443, get list of agents and place it to a variable
	#>
	param (
		[Parameter(Mandatory = $true)]
		[string]$Host,
		[Parameter(Mandatory = $true)]
		[string]$Token
	)
	$script:MC_host_and_port = $Host
	$script:API_token = $Token
	$script:base_url = "https://$Host/api/v2"
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------

if ($PSVersionTable.PSVersion -lt "6.0")
{
	######################## Ignoring cert check error callback #####################
	add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
	[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3, [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12
	####################################################################################
}

$MC_host_and_port = ""
$API_token = ""
$base_url = "https://$Host/api/v2"
$cjblob = New-Object System.Object


