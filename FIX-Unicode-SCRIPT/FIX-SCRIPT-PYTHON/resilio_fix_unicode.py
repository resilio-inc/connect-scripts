#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
resilio_fix_unicode.py

Queries the Resilio Connect Management Console API v2, finds all active
job runs with SE_FS_INVALID_UNICODE_IN_FILE_NAME errors, resolves the
affected directories on disk, and invokes fix_non_utf8_names.py to rename
files and directories whose names contain invalid UTF-8 bytes.

Usage:
    python3 resilio_fix_unicode.py --mc-url https://HOST:8446 --token TOKEN
    python3 resilio_fix_unicode.py --mc-url https://HOST:8446 --token TOKEN --apply
    python3 resilio_fix_unicode.py --mc-url https://HOST:8446 --token TOKEN --apply --log /path/to/run.log

Default mode is dry-run (shows what would be renamed, changes nothing).
Pass --apply to actually rename files.

A .log file is always written (even in dry-run). If --log is not specified,
the file is created automatically next to this script:
  resilio_fix_unicode_YYYYMMDD_HHMMSS.log

Requires fix_non_utf8_names.py in the same directory or on PATH.
"""

import os
import sys
import ssl
import json
import logging
import argparse
import subprocess
import urllib.request
import urllib.error
from pathlib import Path
from datetime import datetime

TARGET_ERROR_CODE = "SE_FS_INVALID_UNICODE_IN_FILE_NAME"
DEFAULT_MAX_ENTRIES = 10000


# ─── Logging setup ────────────────────────────────────────────────────────────

def setup_logging(log_path: str) -> logging.Logger:
    """
    Configure a logger that writes to both the terminal (stdout) and a .log
    file simultaneously. Every print-worthy event goes through this logger so
    the file always contains the complete run history.
    """
    logger = logging.getLogger("resilio_fix")
    logger.setLevel(logging.DEBUG)

    fmt = logging.Formatter("%(asctime)s  %(levelname)-7s  %(message)s",
                            datefmt="%Y-%m-%d %H:%M:%S")

    # File handler — full DEBUG output
    fh = logging.FileHandler(log_path, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    # Console handler — INFO and above (same messages, no timestamp clutter)
    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(logging.INFO)
    ch.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(ch)

    return logger


def default_log_path() -> str:
    """Auto-generate a timestamped .log path next to this script."""
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    return str(Path(__file__).parent / f"resilio_fix_unicode_{ts}.log")


# ─── API ──────────────────────────────────────────────────────────────────────

def _make_ssl_ctx():
    """SSL context with certificate verification disabled (MC uses self-signed cert)."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def api_get(mc_url: str, token: str, path: str) -> dict | list:
    url = mc_url.rstrip("/") + path
    req = urllib.request.Request(url, headers={"Authorization": f"Token {token}"})
    try:
        with urllib.request.urlopen(req, context=_make_ssl_ctx(), timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        raise RuntimeError(f"HTTP {e.code} for {url}: {body}") from e


def get_all_runs(mc_url: str, token: str) -> list[dict]:
    """Fetch all job runs, paginating as needed."""
    limit = 100
    offset = 0
    result = []
    while True:
        data = api_get(mc_url, token, f"/api/v2/runs?limit={limit}&offset={offset}")
        # response shape: {"total": N, "data": [...]} or a plain list
        items = data.get("data", data) if isinstance(data, dict) else data
        if not items:
            break
        result.extend(items)
        total = data.get("total", len(items)) if isinstance(data, dict) else len(items)
        offset += len(items)
        if offset >= total:
            break
    return result


def get_error_files(mc_url: str, token: str,
                    run_id: int, agent_id: int, folderid: str) -> dict:
    path = (
        f"/api/v2/runs/{run_id}/agents/{agent_id}/errors/files"
        f"?error_code={TARGET_ERROR_CODE}"
        f"&folderid={folderid}"
        f"&max_entries={DEFAULT_MAX_ENTRIES}"
    )
    return api_get(mc_url, token, path)


# ─── Directory resolution ─────────────────────────────────────────────────────

def dirs_to_scan(base_path: str, api_files: list[dict]) -> list[str]:
    """
    From the API file list, compute the unique on-disk directories to pass
    to fix_non_utf8_names.py.

    The API returns U+FFFD (replacement character) instead of the invalid
    bytes — the original bytes are lost at the API layer. So we work with
    the parent directories of the affected files rather than their exact
    names.

    If a directory segment in the path also contains U+FFFD (i.e. the
    directory name itself is invalid UTF-8), we walk up to the first
    clean ancestor segment.
    """
    dirs = set()
    for f in api_files:
        rel = f.get("path") or f.get("name") or ""
        # Take only the directory portion of the relative path
        rel_dir = os.path.dirname(rel)
        # Walk up while the current segment contains a replacement char
        while rel_dir and "\ufffd" in os.path.basename(rel_dir):
            rel_dir = os.path.dirname(rel_dir)
        if rel_dir and "\ufffd" not in rel_dir:
            full = os.path.join(base_path, rel_dir)
        else:
            # File is in the root, or the directory name is also broken —
            # scan the entire base_path
            full = base_path
        dirs.add(full)
    return sorted(dirs) if dirs else [base_path]


# ─── Task collection from API ─────────────────────────────────────────────────

def collect_tasks(mc_url: str, token: str, log: logging.Logger) -> list[dict]:
    """
    Returns a list of tasks in the form:
      {
        "run_id": 14,
        "run_name": "MESH Hybrid Work Job",
        "agent_id": 5,
        "folderid": "3f88...",
        "base_path": "/mnt/hybrid",
        "dirs": ["/mnt/hybrid"],
        "file_count": 2,
      }
    """
    log.info("[*] Fetching job runs...")
    runs = get_all_runs(mc_url, token)
    log.info(f"    Runs found: {len(runs)}")

    tasks = []
    for run in runs:
        run_errors = run.get("errors") or []
        unicode_errors = [
            e for e in run_errors
            if e.get("code_str") == TARGET_ERROR_CODE
        ]
        if not unicode_errors:
            continue

        run_id = run["id"]
        run_name = run.get("name", f"run#{run_id}")
        log.info(f"\n[!] Run '{run_name}' (id={run_id}) has {len(unicode_errors)} Unicode error(s)")

        for err in unicode_errors:
            agent_id = err.get("agent_id")
            folderid = err.get("folderid")
            msg = err.get("message", "")
            log.info(f"    agent_id={agent_id} folderid={folderid[:16]}...")
            log.info(f"    message: {msg}")
            log.info(f"    Fetching affected file list...")

            try:
                resp = get_error_files(mc_url, token, run_id, agent_id, folderid)
            except RuntimeError as e:
                log.error(f"    ERROR fetching files: {e}")
                continue

            base_path = resp.get("path", "")
            api_files = resp.get("files", [])
            size = resp.get("size", len(api_files))

            log.info(f"    Base path:      {base_path}")
            log.info(f"    Files affected: {size}")
            for f in api_files:
                log.info(f"      - {f.get('path') or f.get('name')}")

            if not base_path:
                log.error("    SKIP: base_path is empty")
                continue

            dirs = dirs_to_scan(base_path, api_files)
            log.info(f"    Directories to scan: {dirs}")

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


# ─── Invoking fix_non_utf8_names.py ──────────────────────────────────────────

def find_fix_script() -> str:
    """Locate fix_non_utf8_names.py next to this script or on PATH."""
    # 1. Same directory as this script
    here = Path(__file__).parent / "fix_non_utf8_names.py"
    if here.exists():
        return str(here)
    # 2. Current working directory
    cwd = Path.cwd() / "fix_non_utf8_names.py"
    if cwd.exists():
        return str(cwd)
    # 3. PATH
    import shutil
    found = shutil.which("fix_non_utf8_names.py")
    if found:
        return found
    raise FileNotFoundError(
        "fix_non_utf8_names.py not found. Place it in the same directory as this script."
    )


def run_fix(dirs: list[str], apply: bool, log_path: str,
            encodings: str | None, log: logging.Logger) -> int:
    fix_script = find_fix_script()
    cmd = [sys.executable, fix_script] + dirs
    if apply:
        cmd.append("--apply")
    cmd += ["--log", log_path]
    if encodings:
        cmd += ["--encodings", encodings]

    log.info(f"\n[>] Running: {' '.join(cmd)}")

    # Let fix_non_utf8_names.py write directly to the shared log file and
    # to its own console — do NOT capture output to avoid double logging.
    result = subprocess.run(cmd)

    return result.returncode


# ─── main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--mc-url", required=True,
                        help="Management Console URL, e.g. https://192.168.1.1:8446")
    parser.add_argument("--token", required=True,
                        help="API token (MC → Settings → API)")
    parser.add_argument("--apply", action="store_true",
                        help="Actually rename files (default: dry-run, show plan only)")
    parser.add_argument("--log",
                        help="Path to the .log file (default: auto-generated next to this script)")
    parser.add_argument("--encodings",
                        help="Comma-separated list of candidate encodings "
                             "(passed to fix_non_utf8_names.py; "
                             "default: cp1251,cp866,koi8-r,mac_cyrillic,cp1252,...)")
    args = parser.parse_args()

    log_path = args.log or default_log_path()
    log = setup_logging(log_path)

    log.info("=" * 60)
    log.info(f"  resilio_fix_unicode.py  started")
    log.info(f"  MC URL : {args.mc_url}")
    log.info(f"  Mode   : {'APPLY' if args.apply else 'DRY-RUN'}")
    log.info(f"  Log    : {log_path}")
    log.info("=" * 60)

    if not args.apply:
        log.info("  DRY-RUN MODE — no files will be changed")
        log.info("  Add --apply to perform the renames")
        log.info("=" * 60)

    # 1. Collect tasks from API
    try:
        tasks = collect_tasks(args.mc_url, args.token, log)
    except RuntimeError as e:
        log.error(f"\nAPI ERROR: {e}")
        sys.exit(1)

    if not tasks:
        log.info(f"\n✓ No {TARGET_ERROR_CODE} errors found. All clean!")
        sys.exit(0)

    # 2. Deduplicate directories across all tasks
    all_dirs = []
    seen = set()
    for task in tasks:
        for d in task["dirs"]:
            if d not in seen:
                seen.add(d)
                all_dirs.append(d)

    log.info(f"\n{'='*60}")
    log.info(f"Tasks: {len(tasks)}, unique directories: {len(all_dirs)}")
    for d in all_dirs:
        log.info(f"  {d}")
    log.info("=" * 60)

    # 3. Run fix_non_utf8_names.py
    rc = run_fix(all_dirs, args.apply, log_path, args.encodings, log)

    log.info("")
    if rc == 0:
        if args.apply:
            log.info("✓ Done. Resilio will re-scan the folders automatically.")
        else:
            log.info("✓ Dry-run complete. Re-run with --apply to apply renames.")
    else:
        log.error(f"✗ fix_non_utf8_names.py exited with code {rc}")
        sys.exit(rc)

    log.info(f"\nFull log saved to: {log_path}")


if __name__ == "__main__":
    main()
