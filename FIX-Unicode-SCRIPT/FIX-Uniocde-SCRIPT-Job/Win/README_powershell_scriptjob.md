# Resilio Connect — Unicode Filename Fixer (PowerShell Script Job Edition)

## A quick word before you read further

If you came here looking for `Get-Help .\resilio_fix_unicode_scriptjob.ps1`
— bad news, dear colleague. It won't work. Not because we were lazy, but
because of how Resilio Connect Script Running Jobs actually work under the
hood, and no amount of comment-based help wizardry can fix that. Read the
box below, have a laugh, and then carry on — this README is the `Get-Help`
you were looking for. ✌️

> **Why `Get-Help` politely refuses to cooperate**
>
> `Get-Help` is a file-reader. It opens an actual `.ps1` file sitting on
> disk, parses the `<# .SYNOPSIS ... #>` block at the top, and prints it
> nicely. That's its whole superpower.
>
> But when this script runs as a **Resilio Connect Script Running Job**, it
> doesn't exist as a file anywhere on the agent. The entire script body is
> pasted directly into a text field in the Management Console, and Resilio
> pipes that text straight into `powershell.exe` as inline code. There is no
> `.ps1` file, no path, nothing for `Get-Help` to point at — so even if you
> typed the command perfectly, PowerShell would just shrug and ask "help for
> what, exactly?"
>
> The `.SYNOPSIS` / `.DESCRIPTION` / `.EXAMPLE` / `.LINK` block is still
> there at the top of the master copy — and it's not decorative. It's there
> for **you**, the human reading the source before copy-pasting it into MC.
> Open the file, read the top 70-ish lines, and you've got the same
> information `Get-Help` would have shown you anyway. Consider this README
> the "I-told-you-so" companion document.

---

## What this script does

Fixes the Resilio Connect error:

```
SE_FS_INVALID_UNICODE_IN_FILE_NAME
File 'SPS-2.T1_WFT □_rush.xlsx' has invalid unicode in its name, it won't be synced
```

It queries the Management Console API, finds every job run reporting this
error, locates the affected files and directories on disk, and renames them
by replacing invalid UTF-16 surrogate characters with `_`. No Python, no
external dependencies — pure PowerShell, compatible with 5.1 and 7+.

---

## How it's meant to be used

This is the **Script Running Job edition** — built to be pasted whole into
a Resilio Connect Script Running Job (Windows tab, `RUN AS: PowerShell`),
not deployed as a file to every agent. One paste, every Windows agent in
the job runs it.

### Steps

1. Open `resilio_fix_unicode_scriptjob.ps1` in your editor of choice
   (Notepad++, VS Code, whatever survives the office air conditioning).
2. Read the help block at the top. Yes, the one `Get-Help` can't reach.
   It's the same content, just delivered the old-fashioned way — with your
   eyeballs.
3. Edit the configuration block near the top of the script body:

   ```powershell
   $MC_URL  = "https://YOUR_MC_HOST:8446"
   $TOKEN   = "YOUR_API_TOKEN"
   $APPLY   = $false    # $false = dry-run, $true = actually rename files
   $LOG_DIR = $env:TEMP # or an explicit path, e.g. "C:\Logs"
   ```

4. Select all (`Ctrl+A`), copy (`Ctrl+C`).
5. In Management Console: **Configure Jobs → your job → 6. SCRIPT → WINDOWS
   tab → RUN AS: PowerShell** — select the placeholder text and paste over
   it.
6. Save and run the job with `$APPLY = $false` first. Always. Every time.
   Check the log. Then flip it to `$true` and run again for real.

### Where the log goes

A `.log` file is written to `$LOG_DIR` (default: system `%TEMP%`, which on
most agents resolves to `C:\Windows\TEMP` when the job runs under the
system account):

```
resilio_fix_unicode_YYYYMMDD_HHmmss.log
```

It contains everything: which runs/agents had the error, every file and
directory scanned, every rename "was → became", and a final summary. It's
deliberately verbose — when something looks off, the log is where the
answer lives.

---

## Master copy discipline

This `.ps1` file in the toolkit repository **is the master copy**. Treat
the text pasted into Management Console as a deployed copy, not a working
draft. If something needs fixing — fix it here, re-paste into MC, and keep
moving. Editing the pasted version live inside MC's text box and forgetting
to bring the fix back here is exactly how desync happens, and exactly the
kind of mess this whole toolkit exists to clean up. The irony would not be
lost on anyone.

---

## Compatibility notes

- **PowerShell 5.1+** required (the script checks at startup and tells you
  exactly which Windows version you're on and where to get WMF 5.1 if
  you're stuck on something prehistoric like Server 2012).
- **PowerShell 7+** works too — version check passes, no extra steps.
- No Python, no modules to install, no internet access needed beyond
  reaching your own Management Console.
- Rename engine uses `MoveFileW` via P/Invoke directly, because
  `Rename-Item` and `[System.IO.File]::Move()` both choke on filenames
  containing unpaired UTF-16 surrogates — which is exactly the kind of
  filename this script exists to fix.

---

## TL;DR

`Get-Help` won't work on a script that lives inside a text box. This file
is the help. You're already reading it. You're welcome.
