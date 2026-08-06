#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fix_non_utf8_names.py

Scans specified paths (files and/or directories) for names containing bytes
that are not valid UTF-8, and attempts to:

  1) Auto-detect the original encoding (tries a list of candidate encodings
     and scores each result: script consistency, vowel ratio, alphabet
     membership) and re-encode the name as UTF-8;
  2) If no encoding produces a clean result — replace invalid bytes with "_"
     (fallback).

Unlike a full tree scan, the script accepts an explicit list of paths —
e.g. obtained from the Resilio Connect Management Console API (Jobs/Agents).
Resilio path macros (%HOME%, %DOWNLOADS%, %USERPROFILE%, %FOLDERS_STORAGE%)
are automatically resolved for the current machine (priority: explicit
override -> local agent config -> Resilio documentation defaults).

Each specified directory is processed recursively (including the directory
itself and all its contents); a specified file is treated as a single entity.

By default runs in dry-run mode (only shows what would be renamed).
Actual renames only happen with the --apply flag.

All operations are written to a .log file. When invoked by resilio_fix_unicode.py
the log path is passed via --log and both scripts append to the same file.
When run standalone, a timestamped log is auto-generated next to this script.

Usage:
    python3 fix_non_utf8_names.py /path/to/folder /path/to/file.txt
    python3 fix_non_utf8_names.py "%FOLDERS_STORAGE%/ProjectX" --apply
    python3 fix_non_utf8_names.py --paths-file paths.txt --apply
    cat paths.txt | python3 fix_non_utf8_names.py --paths-file -

No external dependencies — standard library only (Python 3).
"""

import os
import sys
import json
import logging
import platform
import argparse
import unicodedata
from pathlib import Path
from datetime import datetime

# Candidate encodings tried in order. Order only sets priority when scores
# are equal — the actual choice is made by score_candidate().
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
# For non-Cyrillic/Western-European content (e.g. Japanese, Chinese, Korean)
# pass a custom list via --encodings, e.g.:
#   --encodings shift_jis,gb18030,euc-kr,big5,utf-8


# ─── Logging setup ────────────────────────────────────────────────────────────

def setup_logging(log_path: str, append: bool = False) -> logging.Logger:
    """
    Configure a logger that writes to both stdout and a .log file.
    Uses append mode when called from resilio_fix_unicode.py (both scripts
    share one log file); uses write mode when run standalone.
    """
    logger = logging.getLogger("fix_non_utf8")
    logger.setLevel(logging.DEBUG)

    fmt = logging.Formatter("%(asctime)s  %(levelname)-7s  %(message)s",
                            datefmt="%Y-%m-%d %H:%M:%S")

    mode = "a" if append else "w"
    fh = logging.FileHandler(log_path, mode=mode, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    # Force UTF-8 on Windows console (default is CP1252 which can't handle
    # Cyrillic or replacement characters and causes logging errors).
    import io
    stdout_utf8 = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8",
                                   errors="replace", line_buffering=True)
    ch = logging.StreamHandler(stdout_utf8)
    ch.setLevel(logging.INFO)
    ch.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(ch)

    return logger


def default_log_path() -> str:
    """Auto-generate a timestamped .log path next to this script."""
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    return str(Path(__file__).parent / f"fix_non_utf8_names_{ts}.log")


# ─── Resilio agent config & macro resolution ──────────────────────────────────

def find_resilio_agent_config() -> dict:
    """
    Best-effort search for the local Resilio Connect Agent config file
    (config.json) to read explicit path overrides set by the administrator
    (keys: home_folder_path, downloads_folder_path, user_profile_folder_path,
    folders_storage_path). Returns {} if not found.
    """
    home = os.path.expanduser("~")
    candidates = [
        "/etc/resilio-agent/config.json",
        "/etc/resilio-sync/config.json",
        os.path.join(home, ".config", "resilio-agent", "config.json"),
        os.path.join(home, ".config", "resilio-sync", "config.json"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except (OSError, json.JSONDecodeError):
                continue
    return {}


RESILIO_MACRO_NAMES = ("%HOME%", "%DOWNLOADS%", "%USERPROFILE%", "%FOLDERS_STORAGE%")


def resolve_resilio_macros(path_str: str, agent_config: dict,
                            folders_storage_override: str = None,
                            log: logging.Logger = None) -> str:
    """
    Replaces Resilio Connect path macros with real paths for the CURRENT
    machine (POSIX: Linux/macOS — see docs.resilio.com/content/
    reference-information/path_macros/).

    Value resolution priority for each macro:
      1) --folders-storage CLI argument (only for %FOLDERS_STORAGE%)
      2) Explicit value from the local Resilio agent config.json
      3) Resilio documentation default for the current OS

    If %FOLDERS_STORAGE% cannot be resolved at all, the macro is left
    untouched in the string (with a warning) — safer than guessing.
    """
    if not any(m in path_str for m in RESILIO_MACRO_NAMES):
        return path_str

    home = os.path.expanduser("~")
    is_macos = platform.system() == "Darwin"
    default_downloads = (
        os.path.join(home, "Downloads") if is_macos
        else os.path.join(home, "Resilio Connect Agent")
    )

    values = {
        "%HOME%": agent_config.get("home_folder_path") or home,
        "%USERPROFILE%": agent_config.get("user_profile_folder_path") or home,
        "%DOWNLOADS%": agent_config.get("downloads_folder_path") or default_downloads,
        "%FOLDERS_STORAGE%": folders_storage_override or agent_config.get("folders_storage_path"),
    }

    result = path_str
    for macro, value in values.items():
        if macro not in result:
            continue
        if value:
            result = result.replace(macro, value)
        else:
            msg = (f"WARNING: could not resolve macro {macro} "
                   f"(not in local agent config, --folders-storage not provided). "
                   f"Path {path_str!r} left as-is and will likely be skipped.")
            if log:
                log.warning(msg)
            else:
                print(msg, file=sys.stderr)

    return result


# ─── UTF-8 validation ─────────────────────────────────────────────────────────

def contains_surrogates(name: str) -> bool:
    """
    Check if a string contains unpaired UTF-16 surrogates (U+D800-U+DFFF).
    On Windows, os.fsencode() encodes surrogates as CESU-8/WTF-8 bytes
    (e.g. \\uD800 -> \\xed\\xa0\\x80) which are invalid UTF-8 by standard.
    These cannot be decoded to any real encoding — correct fix is to strip them.
    """
    return any(0xD800 <= ord(ch) <= 0xDFFF for ch in name)


def is_valid_utf8(name_bytes: bytes) -> bool:
    try:
        s = name_bytes.decode("utf-8")
        return not contains_surrogates(s)
    except UnicodeDecodeError:
        return False


# ─── Encoding detection ───────────────────────────────────────────────────────

CYRILLIC_VOWELS = set("аеёиоуыэюя")
LATIN_VOWELS = set("aeiouy")

# Standard Russian alphabet (33 letters). Strong discriminator: when one
# Cyrillic encoding (cp866/cp1251/koi8-r/mac_cyrillic) is confused with
# another, the result almost always contains "foreign" Cyrillic letters —
# Ukrainian/Belarusian/Serbian (ї, є, ґ, ў, ј, etc.) that don't appear in
# ordinary Russian filenames. If you work with Ukrainian/Belarusian names,
# add the relevant letters to this set.
RUSSIAN_ALPHABET = set("абвгдежзийклмнопрстуфхцчшщъыьэюяё")

# Encodings designed EXCLUSIVELY for one writing system: a clean result in
# that system is a stronger signal of a correct guess. cp1252/iso-8859-1/
# cp437/cp850 are "omnivorous" 8-bit encodings that accept almost ANY byte
# as a syntactically valid (but not necessarily meaningful) Latin character,
# so they should lose to more specific encodings when scores are equal.
SCRIPT_SPECIFIC_BONUS = {
    "cp1251": 0.05, "cp866": 0.05, "koi8-r": 0.05, "mac_cyrillic": 0.05,
    "iso-8859-5": 0.05, "iso-8859-7": 0.05, "windows-1253": 0.05,
    "windows-1255": 0.05, "windows-1256": 0.05,
    "shift_jis": 0.05, "euc-kr": 0.05, "euc-jp": 0.05,
    "big5": 0.05, "gb18030": 0.05, "gbk": 0.05,
}


def _script_of(ch: str):
    """Rough Unicode script detection by code point range."""
    cp = ord(ch)
    if 0x0400 <= cp <= 0x04FF:
        return "cyrillic"
    if cp <= 0x024F:
        return "latin"
    if 0x0370 <= cp <= 0x03FF:
        return "greek"
    if 0x0590 <= cp <= 0x05FF:
        return "hebrew"
    if 0x0600 <= cp <= 0x06FF:
        return "arabic"
    if 0x4E00 <= cp <= 0x9FFF:
        return "han"
    if 0x3040 <= cp <= 0x30FF:
        return "kana"
    if 0xAC00 <= cp <= 0xD7A3:
        return "hangul"
    return None


def _is_vowel(ch: str, script: str) -> bool:
    if script == "cyrillic":
        return ch.lower() in CYRILLIC_VOWELS
    if script == "latin":
        # NFKD reduces accented letter to base form (è -> e) so we don't
        # have to enumerate every diacritic variant manually.
        base = unicodedata.normalize("NFKD", ch)[0]
        return base.lower() in LATIN_VOWELS
    return False


def score_candidate(s: str):
    """
    Score a decoded string's plausibility as real human text.
    Returns (consistency, combined) floats (higher = better), or None if
    the string is clearly garbage.

    Components:
    - script_consistency: fraction of letters from ONE writing system
      (main filter — mixed scripts almost always mean wrong encoding);
    - vowel_factor: for Cyrillic/Latin, vowel ratio should be reasonable;
      words with no vowels (or almost all vowels) are suspicious in practice;
    - case_factor: mild penalty for suspiciously all-uppercase text
      (common side-effect of encoding confusion, e.g. koi8-r <-> cp1251
      where case is inverted).
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

    from collections import Counter
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
    Try to find the original encoding of a filename's byte string.
    Checks each candidate encoding, scores the result via score_candidate(),
    and picks the best one.
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
    replace everything else with "_". Collapse consecutive "_" into one to
    avoid names like "file____.txt".
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
    Returns (new_name_str, method), where method is one of:
      'ok'            — name is already valid UTF-8, leave it alone
      'guessed:<enc>' — encoding detected and name re-encoded as UTF-8
      'surrogate'     — Windows unpaired surrogate stripped and replaced with "_"
      'fallback'      — encoding unknown, invalid bytes replaced with "_"
    """
    if is_valid_utf8(name_bytes):
        return name_bytes.decode("utf-8"), "ok"

    # Windows NTFS stores surrogate codepoints as CESU-8/WTF-8 byte sequences
    # (e.g. U+D800 -> \xed\xa0\x80). These are not a legacy encoding -
    # skip guess_decode and go straight to sanitize_fallback which strips them.
    try:
        decoded_wtf8 = name_bytes.decode("utf-8", errors="surrogatepass")
        if contains_surrogates(decoded_wtf8):
            clean = sanitize_fallback(name_bytes)
            return clean, "surrogate"
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

def fix_entry_in_place(parent_dir_b: bytes, entry_b: bytes, candidates,
                        apply: bool, log: logging.Logger,
                        stats: dict) -> bytes:
    """
    Check and fix ONE name (file or directory) inside the given parent
    directory. Returns the final byte path to the entry: the new path if
    the rename was actually applied, otherwise the old one (important for
    directories — we need to continue scanning their contents).
    """
    old_path = os.path.join(parent_dir_b, entry_b)
    new_name_str, method = fix_name(entry_b, candidates)

    if method == "ok":
        stats["skipped_ok"] += 1
        return old_path

    new_name_b = os.fsencode(new_name_str)
    new_path = os.path.join(parent_dir_b, new_name_b)
    new_path = ensure_unique(new_path)

    # Human-readable display: decode old name with replacement chars so the
    # log shows something meaningful instead of raw byte escapes.
    old_name_display = entry_b.decode("utf-8", errors="replace")
    new_path_display = os.path.join(
        parent_dir_b.decode("utf-8", errors="replace"), new_name_str
    )

    log.info(f"[{method}]")
    log.info(f"  from: {old_name_display!r}")
    log.info(f"  to:   {new_name_str!r}")

    if method == "surrogate":
        stats["surrogate_count"] += 1
    elif method == "fallback":
        stats["fallback_count"] += 1
    stats["renamed"] += 1

    if apply:
        try:
            os.rename(old_path, new_path)
            log.info(f"  result: renamed OK")
        except OSError as e:
            log.error(f"  result: FAILED — {e}")
            stats["rename_errors"] += 1
    else:
        log.info(f"  result: dry-run, skipped")

    return new_path if apply else old_path


def walk_directory_contents(dir_b: bytes, apply: bool, candidates,
                             log: logging.Logger, stats: dict):
    """
    Recursively (bottom-up) check and fix all CONTENTS of the given
    directory. The directory name itself is not touched here — that must
    be done separately before calling this function.
    Bottom-up order (topdown=False) ensures nested entries are renamed
    before their parent, so paths stay valid throughout.
    """
    for dirpath, dirnames, filenames in os.walk(dir_b, topdown=False):
        for entries in (filenames, dirnames):
            for entry in entries:
                fix_entry_in_place(dirpath, entry, candidates,
                                   apply, log, stats)


def process_input_path(path_str: str, apply: bool, candidates,
                        log: logging.Logger, stats: dict):
    """
    Process ONE path supplied by the user (after macro resolution).
    If it is a file — fix only its name.
    If it is a directory — fix the directory name itself (in its parent),
    then recursively fix everything inside.
    """
    path_b = os.fsencode(path_str)

    if os.path.isfile(path_b):
        parent_b, entry_b = os.path.split(path_b)
        fix_entry_in_place(parent_b, entry_b, candidates, apply, log, stats)

    elif os.path.isdir(path_b):
        stripped = path_b.rstrip(b"/")
        parent_b, entry_b = os.path.split(stripped)
        if parent_b and entry_b:
            new_dir_b = fix_entry_in_place(parent_b, entry_b, candidates,
                                           apply, log, stats)
        else:
            # Filesystem root or path without a parent — leave name alone
            new_dir_b = path_b
        walk_directory_contents(new_dir_b, apply, candidates, log, stats)

    else:
        log.warning(f"SKIPPED (path not found): {path_str!r}")
        stats["not_found"] += 1


# ─── main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "paths", nargs="*",
        help="One or more paths (files or directories) to check. "
             "Resilio path macros are supported: %%HOME%%, %%DOWNLOADS%%, "
             "%%USERPROFILE%%, %%FOLDERS_STORAGE%%",
    )
    parser.add_argument(
        "--paths-file",
        help="File with a list of paths (one per line, '#' = comment), "
             "or '-' to read from stdin.",
    )
    parser.add_argument(
        "--apply", action="store_true",
        help="Actually rename files (default: dry-run, show plan only)",
    )
    parser.add_argument(
        "--log",
        help="Path to the .log file to append to. "
             "If not specified, a timestamped file is created next to this script.",
    )
    parser.add_argument(
        "--encodings",
        help="Comma-separated list of candidate encodings to try "
             "(default: " + ",".join(DEFAULT_CANDIDATE_ENCODINGS) + ")",
    )
    parser.add_argument(
        "--folders-storage",
        help="Explicit value for the %%FOLDERS_STORAGE%% macro if it cannot "
             "be found automatically in the local Resilio agent config",
    )
    args = parser.parse_args()

    all_paths = list(args.paths)
    if args.paths_file:
        if args.paths_file == "-":
            lines = sys.stdin.read().splitlines()
        else:
            with open(args.paths_file, "r", encoding="utf-8") as f:
                lines = f.read().splitlines()
        all_paths.extend(
            line.strip() for line in lines
            if line.strip() and not line.strip().startswith("#")
        )

    if not all_paths:
        parser.error("Specify at least one path (as argument or via --paths-file)")

    candidates = DEFAULT_CANDIDATE_ENCODINGS
    if args.encodings:
        candidates = [e.strip() for e in args.encodings.split(",") if e.strip()]

    agent_config = find_resilio_agent_config()

    # Append mode when --log is given (called from resilio_fix_unicode.py);
    # write mode when running standalone (generate own log file).
    log_path = args.log or default_log_path()
    append_mode = bool(args.log)
    log = setup_logging(log_path, append=append_mode)

    if not append_mode:
        # Standalone run — print header
        log.info("=" * 60)
        log.info("  fix_non_utf8_names.py  started (standalone)")
        log.info(f"  Mode : {'APPLY' if args.apply else 'DRY-RUN'}")
        log.info(f"  Log  : {log_path}")
        log.info("=" * 60)
    else:
        log.info("")
        log.info("--- fix_non_utf8_names.py ---")

    stats = {
        "skipped_ok": 0,
        "renamed": 0,
        "surrogate_count": 0,
        "fallback_count": 0,
        "not_found": 0,
        "rename_errors": 0,
    }

    for raw_path in all_paths:
        resolved_path = resolve_resilio_macros(
            raw_path, agent_config, args.folders_storage, log
        )
        if resolved_path != raw_path:
            log.info(f"[macro] {raw_path!r} -> {resolved_path!r}")
        process_input_path(resolved_path, args.apply, candidates, log, stats)

    log.info("")
    log.info("--- Summary ---")
    log.info(f"Already valid UTF-8 (skipped): {stats['skipped_ok']}")
    log.info(f"Renamed (or proposed):         {stats['renamed']}")
    log.info(f"  of which surrogate stripped:        {stats['surrogate_count']}")
    log.info(f"  of which fallback (_ substitution): {stats['fallback_count']}")
    if stats["not_found"]:
        log.warning(f"Paths not found:               {stats['not_found']}")
    if stats["rename_errors"]:
        log.error(f"Rename errors:                 {stats['rename_errors']}")
    if not args.apply:
        log.info("Dry-run — nothing changed. Re-run with --apply to apply renames.")

    if not append_mode:
        log.info(f"\nFull log saved to: {log_path}")


if __name__ == "__main__":
    main()
