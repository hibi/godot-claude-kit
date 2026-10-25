#!/usr/bin/env bash
# warnings.sh - the GDScript warnings of a Godot 4 project (unused variable, shadowing, integer division, unreachable
# code, missing await ...) as "res://file.gd:LINE: message" lines.
#
#   bash warnings.sh --path <project> [options] [file.gd ...]     files: only report these (res://, relative or absolute)
#
#   --gate RES      the project's parse gate scene (default res://tools/ci/parse_gate.tscn). Without one, gate.sh runs
#                   parse_gate_script.gd from this directory instead, so a project needs nothing added to be checked.
#   --timeout S     wall-clock limit for each engine run (default 120)
#   --no-import     skip the import (only when the .godot/ cache is current)
#
# Measured on Godot 4.7.2, which is why it works the way it does:
#   - Without --debug the engine prints NO warnings at all: --check-only exits 0 silently, the gate says PASS.
#   - With --debug, a script that does not parse stops at a `debug>` prompt. On Windows the engine then never exits,
#     even with stdin closed (on Linux, stdin closed, --check-only crashed with 132 and the gate failed normally).
#     So the gate runs normally first, and the --debug pass only after it passed, under a wall-clock timeout.
#   - An un-awaited call to a coroutine warns only when the project enables debug/gdscript/warnings/missing_await,
#     which is off by default. This script says so when it is off.
#
# Last line and exit code:
#   GODOT-WARN: CLEAN (...)      0   the gate passed and the --debug pass printed no warning (for the files asked)
#   GODOT-WARN: FOUND n (...)    1   n warnings, listed above as res://file.gd:LINE: message
#   GODOT-WARN: FAIL (why)       2   could not check: the gate failed (fix that first), the --debug pass hung, ...
#   GODOT-WARN: NO-ENGINE        3   set GODOT_BIN
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

PROJECT="" GATE="res://tools/ci/parse_gate.tscn" TIMEOUT_S=120 DO_IMPORT=1 FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PROJECT="${2%/}"; shift 2 ;;
    --gate) GATE="$2"; shift 2 ;;
    --timeout) TIMEOUT_S="$2"; shift 2 ;;
    --no-import) DO_IMPORT=0; shift ;;
    -*) echo "GODOT-WARN: FAIL (unknown option '$1')"; exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done
[ -n "$PROJECT" ] && [ -f "$PROJECT/project.godot" ] || { echo "GODOT-WARN: FAIL (no project.godot in --path '$PROJECT')"; exit 2; }
[ -f "$HERE/gate.sh" ] || { echo "GODOT-WARN: FAIL (gate.sh not found next to warnings.sh)"; exit 2; }

# The files to report on, as res:// paths.
PABS=$(cd "$PROJECT" && pwd)
WANT=()
for f in ${FILES[@]+"${FILES[@]}"}; do
  case "$f" in
    res://*) WANT+=("$f") ;;
    /*) WANT+=("res://${f#"$PABS"/}") ;;
    *) if [ -e "$f" ]; then a="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"; WANT+=("res://${a#"$PABS"/}")
       else WANT+=("res://${f#./}"); fi ;;
  esac
done
# A file that is not in the project would match no warning and read as CLEAN - e.g. a repo-root-relative path from
# `git diff` while the project sits in a subdirectory. Refuse it instead.
missing=()
for w in ${WANT[@]+"${WANT[@]}"}; do [ -f "$PROJECT/${w#res://}" ] || missing+=("$w"); done
if [ ${#missing[@]} -gt 0 ]; then
  echo "GODOT-WARN: FAIL (not in the project: ${missing[*]} - pass paths relative to the project, or res:// paths)"
  exit 2
fi
# Warnings switched off project-wide: the --debug pass would print nothing, which is not the same as clean.
we=$(tr -d '\r' < "$PROJECT/project.godot" | sed -n 's/^gdscript\/warnings\/enable=\(.*\)/\1/p' | tail -1)
if [ "$we" = false ]; then
  echo "GODOT-WARN: FAIL (debug/gdscript/warnings/enable=false in project.godot: the engine reports no warnings at all)"
  exit 2
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/godot_warn.XXXXXX")
IMPORT=(); [ "$DO_IMPORT" = 1 ] || IMPORT=(--no-import)
# 1. The ordinary gate. A script that does not parse would hang the --debug pass below.
bash "$HERE/gate.sh" --path "$PROJECT" --gate "$GATE" ${IMPORT[@]+"${IMPORT[@]}"} --timeout "$TIMEOUT_S" \
  --log "$WORK/gate.log" > "$WORK/gate.out" 2>&1
rc=$?
grep '^gate: ' "$WORK/gate.out" | head -1 | sed 's/^/  /'
[ $rc -eq 3 ] && { cat "$WORK/gate.out"; echo "GODOT-WARN: NO-ENGINE (set GODOT_BIN to the Godot 4 executable)"; exit 3; }
if [ $rc -ne 0 ]; then
  sed 's/^/  /' "$WORK/gate.out"
  echo "GODOT-WARN: FAIL (the parse gate did not pass - fix that first; with --debug a parse error can hang the engine)"
  exit 2
fi
# 2. The same gate with --debug: now every script it loads prints its warnings. stdin closed; the timeout is the guard.
bash "$HERE/gate.sh" --path "$PROJECT" --gate "$GATE" --no-import --debug --timeout "$TIMEOUT_S" \
  --log "$WORK/debug.log" < /dev/null > "$WORK/debug.out" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  sed 's/^/  /' "$WORK/debug.out"
  echo "GODOT-WARN: FAIL (the --debug pass did not finish cleanly - log $WORK/debug.log)"
  exit 2
fi

# WARNING: <message>
#    at: GDScript::reload (res://path.gd:LINE)
tr -d '\r' < "$WORK/debug.log" | awk '
  /^WARNING: / { msg = substr($0, 10); next }
  msg != "" && /^[[:space:]]*at: GDScript::reload \(res:\/\// {
    loc = $0; sub(/.*\(/, "", loc); sub(/\)[[:space:]]*$/, "", loc); print loc ": " msg }
  { msg = "" }' | grep -v '^res://addons/' | sort -u | sort -t: -k2,2 -k3,3n > "$WORK/all.txt"
if [ ${#WANT[@]} -gt 0 ]; then
  : > "$WORK/found.txt"
  for w in "${WANT[@]}"; do grep -F "$w:" "$WORK/all.txt" >> "$WORK/found.txt"; done
  scope="${#WANT[@]} file(s) asked"
else
  cp "$WORK/all.txt" "$WORK/found.txt"; scope="whole project"
fi
n=$(grep -c . "$WORK/found.txt")
sed 's/^/  /' "$WORK/found.txt"

ma=$(tr -d '\r' < "$PROJECT/project.godot" | sed -n 's/^gdscript\/warnings\/missing_await=\([0-9]\).*/\1/p' | tail -1)
if [ "${ma:-0}" = 0 ]; then
  echo "  note: debug/gdscript/warnings/missing_await is off (the default): an un-awaited call to a coroutine gives NO"
  echo "        warning here. Check such calls by hand, or enable it (Project Settings > Debug > GDScript)."
fi
if [ "$n" -gt 0 ]; then echo "GODOT-WARN: FOUND $n ($scope)"; exit 1; fi
echo "GODOT-WARN: CLEAN ($scope)"
exit 0
