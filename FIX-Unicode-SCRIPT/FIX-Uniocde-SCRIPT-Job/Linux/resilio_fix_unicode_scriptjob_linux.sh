#!/bin/sh

echo $(date +'%m/%d/%y %H:%M:%S'): Script started on $TAG_AGENT_NAME

python3 - <<'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
resilio_fix_unicode_scriptjob.py

Combined, self-contained version of resilio_fix_unicode.py +
fix_non_utf8_names.py, designed to run as a Resilio Connect Script Running
Job on Linux agents (RUN AS: Shell), embedded inline via a shell heredoc —
no external files need to be deployed to any agent.

Queries the Resilio Connect Management Console API v2, finds all active job
runs with SE_FS_INVALID_UNICODE_IN_FILE_NAME errors, scans the affected
directories on THIS agent and fixes invalid filenames:
  - if the original legacy encoding (cp1251, cp866, koi8-r, cp1252, ...)
    can be confidently detected, the name is re-encoded as proper UTF-8;
  - if not (e.g. unpaired UTF-16 surrogates received from a Windows peer,
    or genuinely undetectable byte garbage), invalid bytes are replaced
    with "_".

Configuration is set via plain variables right below this docstring (not
command-line arguments) so the whole file can be pasted as-is into the
Script field of a Resilio Connect Script Running Job.
"""

import os
import re
import sys
import ssl
import json
import logging
import platform
import unicodedata
import urllib.request
import urllib.error
from pathlib import Path
from datetime import datetime
from collections import Counter

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION — edit these before pasting into the Script field
# ═══════════════════════════════════════════════════════════════════════════

MC_URL  = "https://192.168.128.103:8446"
TOKEN   = "AXTDYOU5YIEL24U4HGAZVFICHHRNOPIZ3YB3O2FVVODVB2GK4KPA"
APPLY   = False        # False = dry-run (report only), True = actually rename
LOG_DIR = "/tmp"        # directory for the timestamped .log file

TARGET_ERROR_CODE   = "SE_FS_INVALID_UNICODE_IN_FILE_NAME"
DEFAULT_MAX_ENTRIES  = 10000

DEFAULT_CANDIDATE_ENCODINGS = [
    "cp1251",      # Windows Cyrillic
    "cp866",       # DOS Cyrillic
    "koi8-r",      # Unix Cyrillic
    "mac_cyrillic",
    "cp1252",      # Windows Western European
    "iso-8859-1",  # Latin-1
    "cp437",       # DOS US/Western
    "cp850",       # DOS Western Europe
]


# ─── Logging setup ────────────────────────────────────────────────────────────

def setup_logging(log_path: str) -> logging.Logger:
    logger = logging.getLogger("resilio_fix_unicode")
    logger.setLevel(logging.DEBUG)

    fmt = logging.Formatter("%(asctime)s  %(levelname)-7s  %(message)s",
                            datefmt="%Y-%m-%d %H:%M:%S")

    fh = logging.FileHandler(log_path, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(logging.INFO)
    ch.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(ch)

    return logger


def default_log_path() -> str:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    return str(Path(LOG_DIR) / f"resilio_fix_unicode_{ts}.log")


# ─── API ──────────────────────────────────────────────────────────────────────

def _make_ssl_ctx():
    """SSL context with certificate verification disabled (MC uses self-signed cert)."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def api_get(mc_url, token, path):
    url = mc_url.rstrip("/") + path
    req = urllib.request.Request(url, headers={"Authorization": f"Token {token}"})
    try:
        with urllib.request.urlopen(req, context=_make_ssl_ctx(), timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        raise RuntimeError(f"HTTP {e.code} for {url}: {body}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"Connection failed for {url}: {e.reason}") from e
    except (OSError, TimeoutError) as e:
        raise RuntimeError(f"Network error for {url}: {e}") from e
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Invalid JSON response from {url}: {e}") from e


def get_all_runs(mc_url, token):
    """Fetch all job runs, paginating as needed."""
    limit = 100
    offset = 0
    result = []
    while True:
        data = api_get(mc_url, token, f"/api/v2/runs?limit={limit}&offset={offset}")
        items = data.get("data", data) if isinstance(data, dict) else data
        if not items:
            break
        result.extend(items)
        total = data.get("total", len(items)) if isinstance(data, dict) else len(items)
        offset += len(items)
        if offset >= total:
            break
    return result


def get_error_files(mc_url, token, run_id, agent_id, folderid):
    path = (
        f"/api/v2/runs/{run_id}/agents/{agent_id}/errors/files"
        f"?error_code={TARGET_ERROR_CODE}"
        f"&folderid={folderid}"
        f"&max_entries={DEFAULT_MAX_ENTRIES}"
    )
    return api_get(mc_url, token, path)


# ─── Directory resolution ─────────────────────────────────────────────────────

def dirs_to_scan(base_path, api_files):
    """
    From the API file list, compute the unique on-disk directories to scan.
    The API returns U+FFFD instead of invalid bytes — the original bytes are
    lost at the API layer. So we work with the parent directories of the
    affected files rather than their exact names.
    """
    dirs = set()
    for f in api_files:
        rel = f.get("path") or f.get("name") or ""
        rel_dir = os.path.dirname(rel)
        while rel_dir and "\ufffd" in os.path.basename(rel_dir):
            rel_dir = os.path.dirname(rel_dir)
        if rel_dir and "\ufffd" not in rel_dir:
            full = os.path.join(base_path, rel_dir)
        else:
            full = base_path
        dirs.add(full)
    return sorted(dirs) if dirs else [base_path]


# ─── Task collection from API ─────────────────────────────────────────────────

def collect_tasks(mc_url, token, log):
    log.info("[*] Fetching job runs...")
    runs = get_all_runs(mc_url, token)
    log.info(f"    Runs found: {len(runs)}")

    tasks = []
    for run in runs:
        run_errors = run.get("errors") or []
        unicode_errors = [e for e in run_errors if e.get("code_str") == TARGET_ERROR_CODE]
        if not unicode_errors:
            continue

        run_id = run["id"]
        run_name = run.get("name", f"run#{run_id}")
        log.info(f"\n[!] Run '{run_name}' (id={run_id}) has {len(unicode_errors)} Unicode error(s)")
        log.info(f"    Status : {run.get('status')}")
        log.info(f"    Type   : {run.get('type')}")

        for err in unicode_errors:
            agent_id = err.get("agent_id")
            folderid = err.get("folderid")
            msg = err.get("message", "")
            log.info(f"\n    [error] agent_id  = {agent_id}")
            log.info(f"    [error] folderid  = {folderid}")
            log.info(f"    [error] message   = {msg}")
            log.info(f"    Fetching affected file list...")

            try:
                resp = get_error_files(mc_url, token, run_id, agent_id, folderid)
            except RuntimeError as e:
                log.error(f"    ERROR fetching files: {e}")
                continue

            base_path = resp.get("path", "")
            api_files = resp.get("files", [])
            size = resp.get("size", len(api_files))

            log.info(f"    Base path      : {base_path}")
            log.info(f"    Files affected : {size}")
            for f in api_files:
                log.info(f"      - {f.get('path') or f.get('name')}")

            if not base_path:
                log.warning("    SKIP: base_path is empty")
                continue

            if not os.path.exists(base_path):
                log.warning(f"    SKIP: path '{base_path}' does not exist on this agent ({platform.node()})")
                continue

            dirs = dirs_to_scan(base_path, api_files)
            log.info(f"    Dirs to scan   : {', '.join(dirs)}")

            tasks.append({
                "run_id": run_id,
                "run_name": run_name,
                "agent_id": agent_id,
                "folderid": folderid,
                "base_path": base_path,
                "dirs": dirs,
                "file_count": size,
            })

    return tasks


# ─── UTF-8 / surrogate validation ─────────────────────────────────────────────

def contains_surrogates(name: str) -> bool:
    """
    Check if a string contains unpaired UTF-16 surrogates (U+D800-U+DFFF).
    These can show up in filenames synced from a Windows peer where NTFS
    accepted them via low-level Win32 calls. They are not a legacy encoding —
    there is nothing to "guess", they must simply be stripped.
    """
    return any(0xD800 <= ord(ch) <= 0xDFFF for ch in name)


def is_valid_utf8(name_bytes: bytes) -> bool:
    try:
        s = name_bytes.decode("utf-8")
        return not contains_surrogates(s)
    except UnicodeDecodeError:
        return False


# ─── Encoding detection heuristics ────────────────────────────────────────────

CYRILLIC_VOWELS = set("аеёиоуыэюя")
LATIN_VOWELS = set("aeiouy")

RUSSIAN_ALPHABET = set("абвгдежзийклмнопрстуфхцчшщъыьэюяё")

SCRIPT_SPECIFIC_BONUS = {
    "cp1251": 0.05, "cp866": 0.05, "koi8-r": 0.05, "mac_cyrillic": 0.05,
    "iso-8859-5": 0.05, "iso-8859-7": 0.05, "windows-1253": 0.05,
    "windows-1255": 0.05, "windows-1256": 0.05,
    "shift_jis": 0.05, "euc-kr": 0.05, "euc-jp": 0.05,
    "big5": 0.05, "gb18030": 0.05, "gbk": 0.05,
}


def _script_of(ch: str):
    cp = ord(ch)
    if 0x0400 <= cp <= 0x04FF: return "cyrillic"
    if cp <= 0x024F: return "latin"
    if 0x0370 <= cp <= 0x03FF: return "greek"
    if 0x0590 <= cp <= 0x05FF: return "hebrew"
    if 0x0600 <= cp <= 0x06FF: return "arabic"
    if 0x4E00 <= cp <= 0x9FFF: return "han"
    if 0x3040 <= cp <= 0x30FF: return "kana"
    if 0xAC00 <= cp <= 0xD7A3: return "hangul"
    return None


def _is_vowel(ch: str, script: str) -> bool:
    if script == "cyrillic":
        return ch.lower() in CYRILLIC_VOWELS
    if script == "latin":
        base = unicodedata.normalize("NFKD", ch)[0]
        return base.lower() in LATIN_VOWELS
    return False


def score_candidate(s: str):
    """
    Score a decoded string's plausibility as real human text.
    Returns (consistency, combined) floats (higher = better), or None if
    the string is clearly garbage.
    """
    if not s or "\ufffd" in s:
        return None
    if any(ord(ch) < 0x20 and ch != "\t" for ch in s):
        return None

    non_ascii_chars = [ch for ch in s if ord(ch) > 127]
    letters = [ch for ch in non_ascii_chars if ch.isalpha()]
    if not letters:
        return 0.3, 0.3

    alpha_density = len(letters) / len(non_ascii_chars)

    scripts = [_script_of(ch) for ch in letters]
    known = [sc for sc in scripts if sc]
    if not known:
        return None

    common_script, count = Counter(known).most_common(1)[0]
    consistency = count / len(letters)

    combined = consistency
    if common_script in ("cyrillic", "latin") and len(letters) >= 2:
        vowels = sum(1 for ch in letters if _is_vowel(ch, common_script))
        vowel_ratio = vowels / len(letters)
        if vowel_ratio == 0:
            vowel_factor = 0.3
        elif vowel_ratio > 0.75:
            vowel_factor = 0.5
        else:
            vowel_factor = 1.0
        combined *= vowel_factor

        upper = sum(1 for ch in letters if ch.isupper())
        if upper / len(letters) > 0.7:
            combined *= 0.85

    if common_script == "cyrillic":
        non_standard = sum(1 for ch in letters if ch.lower() not in RUSSIAN_ALPHABET)
        if non_standard:
            combined *= 0.15 ** non_standard

    combined *= alpha_density

    return consistency, combined


def guess_decode(name_bytes: bytes, candidates):
    """
    Try to find the original legacy encoding of a filename's byte string.
    Returns (decoded_str, encoding_name) or (None, None).
    """
    THRESHOLD = 0.9
    COMBINED_THRESHOLD = 0.85

    best_enc = None
    best_combined = -1.0
    best_decoded = None

    for enc in candidates:
        try:
            decoded = name_bytes.decode(enc)
        except (UnicodeDecodeError, LookupError):
            continue
        result = score_candidate(decoded)
        if result is None:
            continue
        consistency, combined = result
        if consistency < THRESHOLD:
            continue
        combined += SCRIPT_SPECIFIC_BONUS.get(enc, 0.0)
        if combined > best_combined:
            best_combined = combined
            best_enc = enc
            best_decoded = decoded

    if best_decoded is not None and best_combined >= COMBINED_THRESHOLD:
        return best_decoded, best_enc

    return None, None


def sanitize_fallback(name_bytes: bytes) -> str:
    """
    Last resort: walk the bytes, keep whatever forms valid UTF-8 (or ASCII),
    replace everything else with "_". Collapse consecutive "_" to avoid
    names like "file____.txt".
    """
    out = []
    i = 0
    n = len(name_bytes)
    while i < n:
        matched = False
        for length in (4, 3, 2, 1):
            chunk = name_bytes[i:i + length]
            try:
                ch = chunk.decode("utf-8")
            except UnicodeDecodeError:
                continue
            out.append(ch)
            i += length
            matched = True
            break
        if not matched:
            out.append("_")
            i += 1

    result = "".join(out)
    while "__" in result:
        result = result.replace("__", "_")
    return result.strip("_") or "_"


def fix_name(name_bytes: bytes, candidates):
    """
    Returns (new_name_str, method):
      'ok'              — already valid UTF-8, left alone
      'guessed:<enc>'   — legacy encoding detected, re-encoded as UTF-8
      'surrogate'       — unpaired UTF-16 surrogate stripped (replaced with "_")
      'fallback'        — encoding undetectable, invalid bytes replaced with "_"
    """
    if is_valid_utf8(name_bytes):
        return name_bytes.decode("utf-8"), "ok"

    # Surrogates (most often arriving from a Windows peer) are not a legacy
    # encoding — skip straight to sanitize_fallback which strips them.
    try:
        decoded_wtf8 = name_bytes.decode("utf-8", errors="surrogatepass")
        if contains_surrogates(decoded_wtf8):
            return sanitize_fallback(name_bytes), "surrogate"
    except (UnicodeDecodeError, TypeError):
        pass

    decoded, enc = guess_decode(name_bytes, candidates)
    if decoded is not None:
        return decoded, f"guessed:{enc}"

    return sanitize_fallback(name_bytes), "fallback"


def ensure_unique(path_b: bytes) -> bytes:
    """If a path with that name already exists, append _1, _2, ..."""
    if not os.path.exists(path_b):
        return path_b
    base, ext = os.path.splitext(path_b)
    i = 1
    while True:
        candidate = base + f"_{i}".encode("ascii") + ext
        if not os.path.exists(candidate):
            return candidate
        i += 1


# ─── Core rename logic ────────────────────────────────────────────────────────

def fix_entry_in_place(parent_dir_b, entry_b, candidates, apply, log, stats, rename_log, rename_seen):
    """
    Check and fix ONE name (file or directory) inside the given parent
    directory. Returns the final byte path to the entry: the new path if
    the rename was actually applied, otherwise the old one.
    """
    old_path = os.path.join(parent_dir_b, entry_b)
    new_name_str, method = fix_name(entry_b, candidates)

    if method == "ok":
        stats["skipped_ok"] += 1
        return old_path

    new_name_b = os.fsencode(new_name_str)
    new_path = os.path.join(parent_dir_b, new_name_b)
    new_path = ensure_unique(new_path)

    old_name_display = entry_b.decode("utf-8", errors="replace")
    new_name_display = os.fsdecode(os.path.basename(new_path))
    dir_display = parent_dir_b.decode("utf-8", errors="replace")
    type_tag = "[DIR] " if os.path.isdir(old_path) else "[FILE]"

    if method == "surrogate":
        stats["surrogate_count"] += 1
    elif method == "fallback":
        stats["fallback_count"] += 1
    stats["renamed"] += 1

    if apply:
        try:
            os.rename(old_path, new_path)
            msg = (f"{type_tag} [RENAMED] from: '{old_name_display}'  ->  "
                   f"to: '{new_name_display}'  dir: '{dir_display}'  method: {method}")
            log.info(msg)
            result_path = new_path
        except OSError as e:
            msg = (f"{type_tag} [ERROR]   from: '{old_name_display}'  error: {e}  "
                   f"dir: '{dir_display}'")
            log.error(msg)
            stats["rename_errors"] += 1
            result_path = old_path
    else:
        msg = (f"{type_tag} [DRY-RUN] from: '{old_name_display}'  ->  "
               f"to: '{new_name_display}'  dir: '{dir_display}'  method: {method}")
        log.info(msg)
        result_path = old_path

    if msg not in rename_seen:
        rename_seen.add(msg)
        rename_log.append(msg)

    return result_path


def repair_directory(root_path, apply, candidates, log, rename_log, rename_seen):
    """
    Recursively (bottom-up) check and fix all entries under root_path,
    including root_path's own name. Bottom-up order ensures children are
    renamed before their parent, so paths stay valid throughout.
    """
    stats = {
        "scanned": 0, "skipped_ok": 0, "renamed": 0,
        "surrogate_count": 0, "fallback_count": 0, "rename_errors": 0,
    }

    root_b = os.fsencode(root_path)

    log.info("  Collecting entries...")
    all_entries = []
    for dirpath, dirnames, filenames in os.walk(root_b, topdown=False):
        for entry in filenames:
            all_entries.append((dirpath, entry))
        for entry in dirnames:
            all_entries.append((dirpath, entry))
    log.info(f"  Found {len(all_entries)} entries total")

    for parent_dir_b, entry_b in all_entries:
        stats["scanned"] += 1
        name_display = entry_b.decode("utf-8", errors="replace")
        if is_valid_utf8(entry_b):
            log.info(f"  [OK]    '{name_display}'")
            stats["skipped_ok"] += 1
            continue
        fix_entry_in_place(parent_dir_b, entry_b, candidates, apply, log,
                           stats, rename_log, rename_seen)

    return stats


# ─── main ─────────────────────────────────────────────────────────────────────

def main():
    log_path = default_log_path()
    log = setup_logging(log_path)

    log.info("=" * 70)
    log.info("  resilio_fix_unicode_scriptjob.py")
    log.info(f"  Started   : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.info(f"  Agent     : {platform.node()}")
    log.info(f"  Python    : {sys.version.split()[0]}")
    log.info(f"  OS        : {platform.platform()}")
    log.info(f"  MC URL    : {MC_URL}")
    log.info(f"  Mode      : {'APPLY - files WILL be renamed' if APPLY else 'DRY-RUN - no changes will be made'}")
    log.info(f"  Log file  : {log_path}")
    log.info("=" * 70)

    if not APPLY:
        log.info("  *** DRY-RUN MODE - no files will be changed ***")
        log.info("  *** Set APPLY = True at the top of the script to perform renames ***")
        log.info("=" * 70)

    log.info("")
    log.info(f"[*] Querying MC API: {MC_URL}/api/v2/runs")
    try:
        tasks = collect_tasks(MC_URL, TOKEN, log)
    except RuntimeError as e:
        log.error(f"FATAL: cannot connect to MC API: {e}")
        sys.exit(1)

    if not tasks:
        log.info("")
        log.info(f"No {TARGET_ERROR_CODE} errors found (or none on this agent). All clean!")
        log.info(f"\nFinished in {0:.1f}s")
        sys.exit(0)

    all_dirs = []
    seen_dirs = set()
    for task in tasks:
        for d in task["dirs"]:
            if d not in seen_dirs:
                seen_dirs.add(d)
                all_dirs.append(d)

    log.info("")
    log.info("=" * 70)
    log.info(f"Unique directories to process: {len(all_dirs)}")
    for d in all_dirs:
        log.info(f"  {d}")
    log.info("=" * 70)

    grand_total = {
        "scanned": 0, "skipped_ok": 0, "renamed": 0,
        "surrogate_count": 0, "fallback_count": 0, "rename_errors": 0,
    }
    rename_log = []
    rename_seen = set()

    for d in all_dirs:
        log.info("")
        log.info("=" * 70)
        log.info(f"Processing: {d}")
        log.info("=" * 70)

        stats = repair_directory(d, APPLY, DEFAULT_CANDIDATE_ENCODINGS, log,
                                 rename_log, rename_seen)

        for k in grand_total:
            grand_total[k] += stats.get(k, 0)

        log.info("")
        log.info("  Directory result:")
        log.info(f"    Scanned : {stats['scanned']}")
        log.info(f"    Clean   : {stats['skipped_ok']}")
        log.info(f"    Renamed : {stats['renamed']} "
                 f"(surrogate: {stats['surrogate_count']}, "
                 f"fallback: {stats['fallback_count']}, "
                 f"guessed: {stats['renamed'] - stats['surrogate_count'] - stats['fallback_count']})")
        log.info(f"    Errors  : {stats['rename_errors']}")

    if rename_log:
        log.info("")
        log.info("=" * 70)
        log.info(f"ALL RENAME OPERATIONS ({len(rename_log)} total):")
        log.info("=" * 70)
        for entry in rename_log:
            log.info(entry)

    log.info("")
    log.info("=" * 70)
    log.info("FINAL SUMMARY")
    log.info("=" * 70)
    log.info(f"Finished   : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.info(f"Agent      : {platform.node()}")
    log.info(f"Mode       : {'APPLY' if APPLY else 'DRY-RUN'}")
    log.info("")
    log.info(f"Dirs processed  : {len(all_dirs)}")
    log.info(f"Entries scanned : {grand_total['scanned']}")
    log.info(f"  Clean (OK)    : {grand_total['skipped_ok']}")
    log.info(f"  Renamed       : {grand_total['renamed']}")
    log.info(f"    Encoding guessed : {grand_total['renamed'] - grand_total['surrogate_count'] - grand_total['fallback_count']}")
    log.info(f"    Surrogate stripped: {grand_total['surrogate_count']}")
    log.info(f"    Fallback (_)      : {grand_total['fallback_count']}")
    if grand_total["rename_errors"] > 0:
        log.error(f"  Errors        : {grand_total['rename_errors']}")
    else:
        log.info(f"  Errors        : 0")
    log.info("")
    if not APPLY:
        log.warning("DRY-RUN complete. Set APPLY = True to apply renames.")
    else:
        if grand_total["renamed"] > 0:
            log.info("Done. Resilio will re-scan the folders automatically.")
        else:
            log.info("Done. No files needed renaming.")
    log.info("")
    log.info(f"Log saved to: {log_path}")
    log.info("=" * 70)

    sys.exit(1 if grand_total["rename_errors"] > 0 else 0)


if __name__ == "__main__":
    main()
PYEOF
PY_EXIT=$?

echo $(date +'%m/%d/%y %H:%M:%S'): Script finished on $TAG_AGENT_NAME
exit $PY_EXIT
