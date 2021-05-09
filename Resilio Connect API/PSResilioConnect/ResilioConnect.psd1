﻿<#	
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2019 v5.6.160
	 Created on:   	9/18/2019 12:46 PM
	 Created by:   	LoneBot
	 Organization: 	
	 Filename:     	
	 -------------------------------------------------------------------------
	 Module Manifest
	-------------------------------------------------------------------------
	 Module Name: 
	===========================================================================
#>


@{
	
	# Script module or binary module file associated with this manifest
	RootModule = 'ResilioConnect.psm1'
	
	# Version number of this module.
	ModuleVersion = '2.11.7.1'
	
	# ID used to uniquely identify this module
	GUID = '295f76f4-3447-4b77-9571-780625279be6'
	
	# Author of this module
	Author = 'Roman Zanin'
	
	# Company or vendor of this module
	# CompanyName = ''
	
	# Copyright statement for this module
	# Copyright = ''
	
	# Description of the functionality provided by this module
	Description = 'Management Console API wrapper'
	
	# Minimum version of the Windows PowerShell engine required by this module
	PowerShellVersion = '4.0'
	
	# Name of the Windows PowerShell host required by this module
	PowerShellHostName = ''
	
	# Minimum version of the Windows PowerShell host required by this module
	PowerShellHostVersion = ''
	
	# Minimum version of the .NET Framework required by this module
	DotNetFrameworkVersion = '2.0'
	
	# Minimum version of the common language runtime (CLR) required by this module
	CLRVersion = '2.0.50727'
	
	# Processor architecture (None, X86, Amd64, IA64) required by this module
	ProcessorArchitecture = 'None'
	
	# Modules that must be imported into the global environment prior to importing
	# this module
	RequiredModules = @()
	
	# Assemblies that must be loaded prior to importing this module
	RequiredAssemblies = @()
	
	# Script files (.ps1) that are run in the caller's environment prior to
	# importing this module
	ScriptsToProcess = @()
	
	# Type files (.ps1xml) to be loaded when importing this module
	TypesToProcess = @()
	
	# Format files (.ps1xml) to be loaded when importing this module
	FormatsToProcess = @()
	
	# Modules to import as nested modules of the module specified in
	# ModuleToProcess
	NestedModules = @()
	
	# Functions to export from this module
	FunctionsToExport = 'Add-AgentTag',
	'Add-AgentToGroup',
	'Add-AgentToJobRun',
	'Find-Agents',
	'Find-ConnectJobRuns',
	'Find-ConnectJobs',
	'Find-ConnectObjects',
	'Find-Groups',
	'Get-Agents',
	'Get-ConnectJobRuns',
	'Get-ConnectJobs',
	'Get-Groups',
	'Initialize-ResilioMCConnection',
	'Invoke-ConnectFunction',
	'Remove-Agent',
	'Remove-AgentTag',
	'Remove-AgentFromGroup',
	'Remove-AgentFromJobRun',
	'Remove-ConnectJob',
	'Set-AgentsToGroup',
	'Start-ConnectJob',
	'Stop-ConnectJob',
	'Update-ConnectJobFromBlob',
	'Initialize-ConnectJobBlob',
	'Add-GroupToBlob',
	'Add-AgentToBlob',
	'Add-ScriptToBlob',
	'Add-SchedulerToBlob',
	'New-ConnectJobFromBlob',
	'ConvertFrom-UnixTime',
	'ConvertTo-UnixTime',
	'New-Profile',
	'Get-Profiles',
	'Find-Profiles',
	'Update-Profile',
	'Remove-Profile'
	
	# DSC class resources to export from this module.
	#DSCResourcesToExport = ''
	
	# List of all modules packaged with this module
	ModuleList = @()
	
	# List of all files packaged with this module
	FileList = @()
	
	# Private data to pass to the module specified in ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
	PrivateData = @{
		
		#Support for PowerShellGet galleries.
		PSData = @{
			
			# Tags applied to this module. These help with module discovery in online galleries.
			# Tags = @()
			
			# A URL to the license for this module.
			# LicenseUri = ''
			
			# A URL to the main website for this project.
			# ProjectUri = ''
			
			# A URL to an icon representing this module.
			# IconUri = ''
			
			# ReleaseNotes of this module
			# ReleaseNotes = ''
			
		} # End of PSData hashtable
		
	} # End of PrivateData hashtable
}








