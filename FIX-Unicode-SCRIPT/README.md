# Resilio Connect — Unicode Filename Fixer Toolkit

Toolkit for detecting and fixing files and directories whose names contain
invalid Unicode characters, causing Resilio Connect to report:

```
SE_FS_INVALID_UNICODE_IN_FILE_NAME
File 'SPS-2.T1_WFT ������_rush.xlsx' has invalid unicode in its name,
it won't be synced
```

---

## What's in the box

| File | Platform | Purpose |
|---|---|---|
| `resilio_fix_unicode.py` | Linux | Orchestrator — queries MC API, finds affected directories, calls the engine |
| `resilio_fix_unicode_wrapper.ps1` | Windows | Same orchestrator, PowerShell wrapper around the Python engine |
| `fix_non_utf8_names.py` | Linux + Windows | Engine — detects encoding, renames files and directories |

---

## How it works

### Why do invalid filenames appear?

**On Linux:** Files copied from old Windows systems (Windows-1251, CP866,
KOI8-R) or Western European systems (CP1252) carry filenames encoded in a
legacy 8-bit encoding. Linux filesystems (ext4, xfs, btrfs) store filenames
as raw bytes without any encoding validation — the bytes land on disk as-is.
Resilio Connect requires valid UTF-8 for syncing and flags these files.

**On Windows (NTFS):** Filenames are stored internally as UTF-16 code units.
NTFS accepts any 16-bit value including unpaired surrogates (U+D800–U+DFFF)
which are technically invalid in Unicode. Old applications and low-level tools
can create such files. Resilio Connect cannot sync them to other platforms.

### Fix logic

1. **Orchestrator** queries the MC API (`/api/v2/runs`) to find job runs
   with `SE_FS_INVALID_UNICODE_IN_FILE_NAME` errors.
2. For each error it calls `/api/v2/runs/:id/agents/:id/errors/files` to get
   the base path on disk.
3. The **engine** (`fix_non_utf8_names.py`) scans the directory recursively
   (bottom-up so nested entries are renamed before their parent) and for each
   invalid name:
   - **Linux:** tries to detect the original encoding (cp1251, cp866, koi8-r,
     mac_cyrillic, cp1252, ...) using a scoring heuristic (script consistency,
     vowel ratio, alphabet membership) and re-encodes the name as UTF-8.
   - **Windows:** detects unpaired surrogates (CESU-8/WTF-8 byte sequences)
     and strips them, replacing with `_`.
   - **Fallback:** if encoding cannot be determined, invalid bytes are replaced
     with `_`.
4. All operations are written to a `.log` file (timestamped, UTF-8).

---

## Requirements

### Linux
- Python 3.10+
- No external dependencies (standard library only)

### Windows
- Python 3.10+ (must be in PATH)
- PowerShell 7.x (`pwsh`) — recommended for correct UTF-8 display
- No external Python dependencies

---

## Usage — Linux

### Run via orchestrator (recommended)

```bash
# Dry-run — show what would be renamed, change nothing
python3 resilio_fix_unicode.py \
  --mc-url https://192.168.128.103:8446 \
  --token YOUR_API_TOKEN

# Apply renames
python3 resilio_fix_unicode.py \
  --mc-url https://192.168.128.103:8446 \
  --token YOUR_API_TOKEN \
  --apply

# Apply with custom log path
python3 resilio_fix_unicode.py \
  --mc-url https://192.168.128.103:8446 \
  --token YOUR_API_TOKEN \
  --apply \
  --log /var/log/resilio_fix.log
```

### Run engine directly (without MC API)

Useful when you know the path and don't need the API:

```bash
# Dry-run on a specific directory
python3 fix_non_utf8_names.py /mnt/hybrid/ProjectFolder

# Apply
python3 fix_non_utf8_names.py /mnt/hybrid/ProjectFolder --apply

# Multiple paths at once
python3 fix_non_utf8_names.py /mnt/hybrid/dir1 /mnt/hybrid/dir2 --apply

# From a file with paths (one per line)
python3 fix_non_utf8_names.py --paths-file paths.txt --apply

# Custom encoding priority (e.g. for Japanese filenames)
python3 fix_non_utf8_names.py /mnt/data --encodings shift_jis,utf-8 --apply
```

### Log file

A `.log` file is always written. If `--log` is not specified, it is created
automatically next to the script:

```
resilio_fix_unicode_20260623_124803.log
```

Log format:
```
2026-06-23 12:48:03  INFO     [guessed:cp1251]
2026-06-23 12:48:03  INFO       from: 'SPS-2.T1_WFT ������_rush.xlsx'
2026-06-23 12:48:03  INFO       to:   'SPS-2.T1_WFT Привет_rush.xlsx'
2026-06-23 12:48:03  INFO       result: renamed OK
```

---

## Usage — Windows

Both files must be in the same directory:
```
fix_non_utf8_names.py              ← Python engine
resilio_fix_unicode_wrapper.ps1    ← PowerShell wrapper
```

Open PowerShell 7 (`pwsh`) and run:

```powershell
# Dry-run
.\resilio_fix_unicode_wrapper.ps1 `
  -McUrl https://192.168.128.103:8446 `
  -Token YOUR_API_TOKEN

# Apply renames
.\resilio_fix_unicode_wrapper.ps1 `
  -McUrl https://192.168.128.103:8446 `
  -Token YOUR_API_TOKEN `
  -Apply

# Apply with custom log path
.\resilio_fix_unicode_wrapper.ps1 `
  -McUrl https://192.168.128.103:8446 `
  -Token YOUR_API_TOKEN `
  -Apply `
  -LogFile C:\Logs\resilio_fix.log

# Custom encoding priority
.\resilio_fix_unicode_wrapper.ps1 `
  -McUrl https://192.168.128.103:8446 `
  -Token YOUR_API_TOKEN `
  -Apply `
  -Encodings "cp1251,cp866,koi8-r"
```

> **Note:** If you see a script execution error, allow local scripts first:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

---

## Recommended workflow

### 1. Always dry-run first!

```bash
# Linux
python3 resilio_fix_unicode.py --mc-url https://HOST:8446 --token TOKEN

# Windows (PowerShell)
.\resilio_fix_unicode_wrapper.ps1 -McUrl https://HOST:8446 -Token TOKEN
```

Review the log file. Check that proposed renames look correct.

### 2. Apply renames

```bash
# Linux
python3 resilio_fix_unicode.py --mc-url https://HOST:8446 --token TOKEN --apply

# Windows
.\resilio_fix_unicode_wrapper.ps1 -McUrl https://HOST:8446 -Token TOKEN -Apply
```

### 3. Restart Resilio Agent

Restart the Resilio Connect Agent on the machine where files were renamed.
The agent will re-scan the folder and the error should disappear from the
Management Console.

---

## Supported encodings (Linux engine)

| Encoding | Typical source |
|---|---|
| `cp1251` | Windows Cyrillic (most common) |
| `cp866` | DOS Cyrillic |
| `koi8-r` | Unix Cyrillic |
| `mac_cyrillic` | macOS Cyrillic |
| `cp1252` | Windows Western European (é, ö, ü, ñ, ...) |
| `iso-8859-1` | Latin-1 |
| `cp437` | DOS US/Western |
| `cp850` | DOS Western European |

For other languages pass a custom list via `--encodings`:

```bash
# Japanese
python3 fix_non_utf8_names.py /path --encodings shift_jis,euc-jp --apply

# Chinese
python3 fix_non_utf8_names.py /path --encodings gb18030,gbk,big5 --apply

# Korean
python3 fix_non_utf8_names.py /path --encodings euc-kr --apply
```

---

## API token

Get your API token from the Resilio Connect Management Console:

**Settings → API → Generate Token**
