#!/usr/bin/env bash
# godot_run.sh - run a Godot 4 project headless, isolated from the real editor settings, and JUDGE the run instead of
# trusting its exit code.
#
#   bash godot_run.sh --path <project> [options] [--] [res://scene.tscn] [extra engine args...]
#
#   --banner REGEX         the line the scene prints when it really finished (e.g. 'DIAG-HEALTH: PASS'). Without it the
#                          best possible verdict is UNVERIFIED: a scene that never ran logs the same bytes as a quiet one.
#   --frames N             --quit-after backstop in FRAMES, not seconds (default 3600). Always on: a run whose scene never
#                          loads does not exit by itself.
#   --timeout S            wall-clock backstop in seconds for each engine process (default 600), if `timeout` exists.
#   --no-import            skip the `--import` step (only when you know the .godot/ cache is current).
#   --import-only          run only the isolated `--import` and stop (GODOT-RUN: IMPORTED). For several processes
#                          on one project: import once, then start each of them with --no-import - parallel
#                          imports would write the same .godot/ cache at once.
#   --allow-engine-errors  report `ERROR:` lines instead of failing on them (SCRIPT ERROR / Parse Error always fail).
#   --log FILE             where to keep the run log (default: a fresh temp dir; the path is printed either way).
#   --home DIR             use DIR as the isolated APPDATA/HOME and KEEP it (default: a throwaway dir, deleted after
#                          the run) - for a caller that needs what the run wrote to user://, e.g. test reports.
#   --windowed             run the scene WITHOUT --headless (the import stays headless): for anything that must render,
#                          e.g. screenshots. --headless never draws a frame. Needs a display (on Linux: xvfb-run).
#
# Engine binary: $GODOT_BIN, else `godot` on PATH. Nothing is hard-coded.
#
# Last line and exit code:
#   GODOT-RUN: PASS          0   banner found, engine exit 0, no SCRIPT ERROR / Parse Error / ERROR / FAIL line
#   GODOT-RUN: FAIL (why)    1
#   GODOT-RUN: UNVERIFIED    2   no --banner given and nothing went wrong - which proves nothing ran either
#   GODOT-RUN: NO-ENGINE     3   no binary found: set GODOT_BIN
#   GODOT-RUN: IMPORTED      0   --import-only: the import exited 0 (which says nothing about the scripts)
set -u

PROJECT="" BANNER="" FRAMES=3600 TIMEOUT_S=600 DO_IMPORT=1 IMPORT_ONLY=0 ALLOW_ERRORS=0 LOG="" KEEP_HOME=""
HEADLESS=--headless
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PROJECT="$2"; shift 2 ;;
    --banner) BANNER="$2"; shift 2 ;;
    --frames) FRAMES="$2"; shift 2 ;;
    --timeout) TIMEOUT_S="$2"; shift 2 ;;
    --no-import) DO_IMPORT=0; shift ;;
    --import-only) IMPORT_ONLY=1; shift ;;
    --allow-engine-errors) ALLOW_ERRORS=1; shift ;;
    --log) LOG="$2"; shift 2 ;;
    --home) KEEP_HOME="$2"; shift 2 ;;
    --windowed) HEADLESS=""; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[ -n "$PROJECT" ] && [ -f "$PROJECT/project.godot" ] || { echo "GODOT-RUN: FAIL (no project.godot in --path '$PROJECT')"; exit 1; }

BIN="${GODOT_BIN:-}"
[ -z "$BIN" ] && command -v godot >/dev/null 2>&1 && BIN=godot
if [ -z "$BIN" ] || ! command -v "$BIN" >/dev/null 2>&1; then
  echo "GODOT-RUN: NO-ENGINE (set GODOT_BIN to the Godot 4 executable; on Windows the *_console.exe build)"
  exit 3
fi

# Isolation: every engine process - the import too - sees a throwaway APPDATA/HOME, so editor settings, recent-project
# lists and user:// data of the real installation are never read or written. (--user-data-dir does not exist in 4.x.)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/godot_run.XXXXXX")
H="${KEEP_HOME:-$WORK/home}"
mkdir -p "$H"
export APPDATA="$H" LOCALAPPDATA="$H" HOME="$H" XDG_DATA_HOME="$H" XDG_CONFIG_HOME="$H" XDG_CACHE_HOME="$H"
[ -n "$LOG" ] || LOG="$WORK/run.log"
IMPORT_LOG="$WORK/import.log"
drop_home() { [ -n "$KEEP_HOME" ] || rm -rf "$WORK/home"; }
show_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

engine() {  # engine <logfile> <args...>
  local out="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_S" "$BIN" "$@" > "$out" 2>&1
  else
    "$BIN" "$@" > "$out" 2>&1
  fi
}

echo "engine:  $("$BIN" --version 2>/dev/null | tr -d '\r')"
if [ "$DO_IMPORT" = 1 ] || [ "$IMPORT_ONLY" = 1 ]; then
  # A fresh clone has no .godot/ cache: until --import runs, class_name types are unknown and correct scripts
  # fail to parse. --import itself does NOT parse-check scripts (a syntax error passes it with exit 0).
  engine "$IMPORT_LOG" --headless --path "$PROJECT" --import
  ie=$?
  if [ $ie -ne 0 ]; then
    echo "import:  exit $ie, log $(show_path "$IMPORT_LOG")"; tr -d '\r' < "$IMPORT_LOG" | tail -5
    echo "GODOT-RUN: FAIL (--import exit $ie)"; drop_home; exit 1
  fi
fi
if [ "$IMPORT_ONLY" = 1 ]; then
  drop_home
  echo "import:  exit 0, log $(show_path "$IMPORT_LOG")"
  echo "GODOT-RUN: IMPORTED"; exit 0
fi

engine "$LOG" ${HEADLESS:+"$HEADLESS"} --path "$PROJECT" --quit-after "$FRAMES" "$@"
code=$?
drop_home

# The engine writes CRLF on Windows: strip CR before matching anything anchored at the line end.
CLEAN="$WORK/run.clean.log"
tr -d '\r' < "$LOG" > "$CLEAN"
echo "run:     exit $code, $(grep -c . "$CLEAN") non-empty lines, log $(show_path "$LOG")"
grep -nE 'SCRIPT ERROR|Parse Error|Compile Error|^ERROR:|^[[:space:]]*FAIL\b|^[[:space:]]*ok\b|PASS|CrashHandler|signal [0-9]+' "$CLEAN" \
  | head -40 | sed 's/^/  | /'

why=""
[ $code -eq 124 ] && why="$why; wall-clock timeout ${TIMEOUT_S}s"
[ $code -ne 0 ] && [ $code -ne 124 ] && why="$why; engine exit $code"
grep -qE 'SCRIPT ERROR|Parse Error|Compile Error' "$CLEAN" && why="$why; script error in log"
if grep -qE '^ERROR:' "$CLEAN"; then
  if [ $ALLOW_ERRORS = 1 ]; then echo "  note: $(grep -cE '^ERROR:' "$CLEAN") ERROR: line(s) allowed by --allow-engine-errors"
  else why="$why; ERROR: line in log"; fi
fi
grep -qE '^[[:space:]]*FAIL\b' "$CLEAN" && why="$why; FAIL line in log"
if [ -n "$BANNER" ] && ! grep -qE "$BANNER" "$CLEAN"; then
  if [ -z "$why" ]; then why="banner /$BANNER/ missing (exit 0 and no error: the scene never ran, or hit --quit-after $FRAMES)"
  else why="$why; banner /$BANNER/ missing"; fi
fi

if [ -n "$why" ]; then echo "GODOT-RUN: FAIL (${why#; })"; exit 1; fi
if [ -z "$BANNER" ]; then echo "GODOT-RUN: UNVERIFIED (no errors, but no --banner: a scene that never ran looks the same)"; exit 2; fi
echo "GODOT-RUN: PASS"
exit 0
