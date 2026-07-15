# AppEnvironmentChecker - Support Team Guide

## Purpose
This script checks the application environment and generates a text report with results.

Main script: Check-AppEnvironment.ps1  
Config file: Config.json
Modules folder: Modules/  
Report output folder: Reports/

## Prerequisites
1. Windows machine.
2. PowerShell available.
3. All project files are in one folder.
4. Administrator rights if using SYSTEM mode.

## Project Structure
- Check-AppEnvironment.ps1: Main runner.
- Config.json: Settings and checks to run.
- Modules/: Individual check modules (AD, Network, SPN, Kerberos, etc.).
- Reports/: Generated reports.
- Utilities/: Optional tools (currently not required by the current SYSTEM implementation).

## Build (Generate Single File)
Use Build.ps1 to create a bundled script in Release.

Output:
- Release/RslConnectToolkit.ps1
- Config*.json files copied to Release

### Build Command
Run from project root:

```powershell
./Build.ps1
```

### Build Parameters
1. BuildType
- Type: string
- Allowed values: Dev, Release
- Default: Dev
- Purpose:
  - Dev creates a self-signed code-signing certificate and signs the output.
  - Release expects an existing trusted code-signing certificate by thumbprint in Build.ps1.

2. Signup
- Type: switch
- Default: False
- Purpose: enables code signing step after build.

### Examples
1. Build only (no signing):

```powershell
./Build.ps1
```

2. Build with signing in Dev mode:

```powershell
./Build.ps1 -Signup
```

3. Build with signing in Release mode:

```powershell
./Build.ps1 -BuildType Release -Signup
```

### Notes
1. Release signing requires a valid code-signing certificate matching the configured thumbprint in Build.ps1.
2. Release output script is auto-generated. Do not manually edit Release/RslConnectToolkit.ps1; edit source files and rebuild.

## How To Run (Normal)
1. Open PowerShell.
2. Go to project folder.
3. Run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Check-AppEnvironment.ps1
```

4. Wait for script completion.
5. Open Reports folder and review latest report.

## How To Run As SYSTEM
Use this when checks must run as NT AUTHORITY\\SYSTEM.

1. Open PowerShell as Administrator.
2. Go to project folder.
3. Run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Check-AppEnvironment.ps1 -RunAsSystem
```

What happens:
- Script creates a temporary scheduled task.
- Task runs script as SYSTEM.
- Task is removed after execution.
- Report is still written to Reports folder in the project path.

## Configuration (Config.json)
In Config.json, section Checks controls what runs.

- true = run check
- false = skip check

Example:

```json
"Checks": {
  "System": true,
  "Network": true,
  "AD": true,
  "Kerberos": true,
  "Application": true,
  "Users": true,
  "SPN": true,
  "Services": true
}
```

Other settings used by modules:
- Domain
- Ports
- SPNs
- Users

## Report Output
Report file name format:

- Report_yyyyMMdd_HHmmss.txt

Report sections:
1. Settings
2. Checks
3. Summary

Each result row contains:
- Check
- Status (PASS, FAIL, WARNING, INFO)
- Detail

## Common Issues
1. Config file not found
- Default behavior uses `Config.json` from the script folder.
- If you use a custom config, pass it explicitly:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Check-AppEnvironment.ps1 -Config MyConfig.json
```

- Confirm the path is correct (absolute or relative to script folder).

2. Module not found
- Verify all expected module files exist in `Modules` with naming pattern `RslCheck-<Name>.psm1`.
- Check that names in `Config.json` > `Checks` match module names (for example `AD` => `RslCheck-AD.psm1`).

3. Function not found in module
- Verify each module exports the expected function name `Invoke-Check<Name>`.
- Example: `RslCheck-AD.psm1` must export `Invoke-CheckAD`.

4. SYSTEM run fails
- Run PowerShell as Administrator.
- Ensure Task Scheduler service is available.
- Verify security policy allows creating and starting scheduled tasks.
- Check errors in terminal output for `LastTaskResult` code.

5. No report file generated
- Verify script completed and no terminating error occurred.
- Check that `Reports` folder is writable.
- Confirm report path shown at end of execution.

6. Verbose messages are missing
- Run with `-Verbose` when you need detailed execution logs.

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Check-AppEnvironment.ps1 -Verbose
```

## Recommended Support Workflow
1. Update Config.json for target environment.
2. Run script in normal mode.
3. If required, run with -RunAsSystem.
4. Share newest report from Reports folder with engineering for analysis.
