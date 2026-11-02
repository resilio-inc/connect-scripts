# Fix-InvalidMtime.ps1

The script fixes invalid modification time (mtime) only for the files that the agent reported with the `SE_FS_INVALID_MODIFICATION_TIME` error, and sets their mtime to the current time.

It gets the list of affected files from the Management Console API, so unlike `fix-mtime.ps1` from this folder it does not scan the folder tree. It works fast even on jobs with millions of files.

## When to use it

| Script | How it finds files | Use when |
|---|---|---|
| `Fix-InvalidMtime.ps1` | Takes the list of files from the Management Console API | The agent already shows `SE_FS_INVALID_MODIFICATION_TIME` in the console |
| `fix-mtime.ps1` | Scans the whole folder tree recursively | The API is not reachable from the agent, or the folder is not in a job yet |

## Requirements

* Windows with PowerShell 5.1 or newer
* `curl.exe` (built into Windows 10 1803+ and Windows Server 2019+)
* Network access from the agent machine to the Management Console API port (8446 by default)
* Management Console API token
* Run the script **on the agent machine** that shows the error, under a user that can update the affected files. The paths returned by the API are local to that agent.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-McUrl` | `$env:RESILIO_MC_URL` | Management Console address, e.g. `https://mc.example.local:8446` |
| `-Token` | `$env:RESILIO_API_TOKEN` | API token. Do not hardcode it in the script |
| `-AgentName` | Computer name | Agent name as shown in the console (case-insensitive) |
| `-AgentId` | – | Agent ID in the console. If set, `-AgentName` is ignored |
| `-ErrorCodes` | `SE_FS_INVALID_MODIFICATION_TIME` | Error codes to process |
| `-MaxEntries` | `10000` | Max number of files requested per error |
| `-WhatIf` | – | Dry run: shows which files would be fixed, changes nothing |

## Script usage

Set the console address and token once per session:

```powershell
$env:RESILIO_MC_URL = "https://mc.example.local:8446"
$env:RESILIO_API_TOKEN = "<token>"
```

Dry run first:

```powershell
.\Fix-InvalidMtime.ps1 -WhatIf
```

Then the real run, with output saved to a log:

```powershell
.\Fix-InvalidMtime.ps1 *> c:\temp\fix-mtime-api.log
```

If the agent name in the console differs from the computer name, the script prints the list of agents with their IDs. Run it again with `-AgentId <id>` or `-AgentName "<name>"`.

## How it works

1. Finds the agent in the console: `GET /api/v2/agents`, matched by name, or directly by `-AgentId`.
2. Reads the agent's current errors (`GET /api/v2/agents/{id}`) and keeps the ones with matching `code_str`.
3. For every error gets the affected files: `GET /api/v2/runs/{job_run_id}/agents/{agent_id}/errors/files?folderid=...&error_code=...&max_entries=...`
4. Joins the job folder path with each relative file path and sets `LastWriteTime` to now. Files that are not on disk anymore are skipped.

At the end it prints a summary: files reported by the API, fixed, skipped and failed.

## Running it regularly

Hybrid Work jobs do not support before/after job script triggers (only Distribution, Consolidation and Script jobs do). To run the fix automatically, create a separate **Script job** for the affected Windows agents with a schedule, and use a command like:

```
powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Fix-InvalidMtime.ps1" -McUrl https://mc.example.local:8446 -Token <token>
```

Each agent finds and fixes only its own errors.

## Notes

* The script sets the current time for **every** file the API reports. It does not check the mtime again.
* Only errors the agent currently reports are processed. After the fix the error disappears from the console on the next job run.
* The console TLS certificate is not verified (`curl -k`), because the console usually uses a self-signed certificate.
* If a job has more affected files than `-MaxEntries`, raise the value or run the script again after the next job run.
