#!/usr/bin/env bash
# ci.sh - ONE verdict for a whole Godot 4 project: import, the parse gate, then every diag harness, each run judged by
# godot_run.sh (banner + error tokens + exit code), never by the engine's exit code alone.
#
#   bash ci.sh --path <project> [options]            run everything, last line GODOT-CI: PASS / FAIL / NO-ENGINE
#   bash ci.sh --path <project> install [options]    vendor ci.sh + godot_run.sh into the project and write a
#                                                    GitHub Actions workflow that runs them
#
#   --gate RES            the parse gate scene (default res://tools/ci/parse_gate.tscn). Required: without it a CI
#                         cannot tell a syntax error from a pass (`--import` exits 0 on one).
#   --min-harnesses N     FAIL when fewer than N diag_*.tscn harnesses are found (default 0). Set it to the number
#                         you have, so a moved or renamed harness directory cannot quietly shrink the run to the gate.
#   --frames N, --timeout S   passed to every run (see godot_run.sh)
#   --out DIR             keep the per-run logs here (default: a fresh temp dir; printed either way)
#   install only:  --dir D (project-relative, default tools/ci), --godot-version V (e.g. 4.7.2-stable; default:
#                  read from the engine in GODOT_BIN / PATH)
#
# Harnesses: every diag_<name>.tscn in the project, outside .godot/, addons/ and directories holding a .gdignore.
# Each one must print the banner "DIAG-<NAME>: PASS" (what the godot-headless-harness template prints).
#
# Last line and exit code:
#   GODOT-CI: PASS (...)     0   gate and every harness PASS
#   GODOT-CI: FAIL (...)     1   names every run that did not pass
#   GODOT-CI: NO-ENGINE      3   no binary: set GODOT_BIN
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

PROJECT="" GATE="res://tools/ci/parse_gate.tscn" MIN_H=0 OUT="" DIR="tools/ci" GVER="" RUNARGS=() ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PROJECT="${2%/}"; shift 2 ;;
    --gate) GATE="$2"; shift 2 ;;
    --min-harnesses) MIN_H="$2"; shift 2 ;;
    --frames|--timeout) RUNARGS+=("$1" "$2"); shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --dir) DIR="${2%/}"; DIR="${DIR#res://}"; shift 2 ;;
    --godot-version) GVER="$2"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[ -n "$PROJECT" ] && [ -f "$PROJECT/project.godot" ] || { echo "GODOT-CI: FAIL (no project.godot in --path '$PROJECT')"; exit 1; }

# The runner: next to this script when vendored into a project, else the sibling godot-run skill.
RUNNER="$HERE/godot_run.sh"
[ -f "$RUNNER" ] || RUNNER="$HERE/../godot-run/godot_run.sh"
[ -f "$RUNNER" ] || { echo "GODOT-CI: FAIL (godot_run.sh not found next to ci.sh or in ../godot-run/)"; exit 1; }

if [ "${ARGS[0]:-}" = install ]; then
  dest="$PROJECT/$DIR"
  for f in "$dest/ci.sh" "$dest/godot_run.sh"; do
    [ -e "$f" ] && { echo "install: $f already exists - not overwriting (delete it to update)"; exit 1; }
  done
  if [ -z "$GVER" ]; then
    BIN="${GODOT_BIN:-godot}"
    # "4.7.2.stable.official.ed1daf0bf" -> "4.7.2-stable", the release tag the workflow downloads
    GVER=$("$BIN" --version 2>/dev/null | tr -d '\r' | sed -nE 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.([a-z0-9]+)\..*/\1-\3/p')
    [ -n "$GVER" ] || { echo "install: cannot read the engine version - pass --godot-version (e.g. 4.7.2-stable)"; exit 1; }
  fi
  # The workflow lives at the repository root; the project may sit in a subdirectory of it.
  root=$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null) || root=""
  if [ -n "$root" ]; then
    # Ask git for the prefix: comparing paths breaks where one directory has two spellings (Git Bash: /tmp = %TEMP%).
    rel=$(git -C "$PROJECT" rev-parse --show-prefix); rel="${rel%/}"; rel="${rel:-.}"
  else
    root="$PROJECT"; rel="."
    echo "install: $PROJECT is not inside a git repository - writing the workflow into the project itself"
  fi
  wf="$root/.github/workflows/godot-ci.yml"
  [ -e "$wf" ] && { echo "install: $wf already exists - not overwriting"; exit 1; }
  mkdir -p "$dest" "$(dirname "$wf")"
  cp "$HERE/ci.sh" "$dest/ci.sh"
  cp "$RUNNER" "$dest/godot_run.sh"
  sed -e "s|__GODOT_VERSION__|$GVER|g" -e "s|__PROJECT__|$rel|g" -e "s|__CI__|$rel/$DIR/ci.sh|g" \
    "$HERE/templates/godot-ci.yml" > "$wf"
  echo "wrote res://$DIR/ci.sh, res://$DIR/godot_run.sh and $wf (Godot $GVER, project dir '$rel')"
  echo "next: run 'bash $rel/$DIR/ci.sh --path $rel' locally first; commit all three files."
  exit 0
fi
[ ${#ARGS[@]} -eq 0 ] || { echo "GODOT-CI: FAIL (unknown argument '${ARGS[0]}')"; exit 1; }

[ -n "$OUT" ] || OUT=$(mktemp -d "${TMPDIR:-/tmp}/godot_ci.XXXXXX")
mkdir -p "$OUT"
show_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

gdignored() {  # gdignored <file>: is any directory between the file and the project root marked with .gdignore?
  local d; d=$(dirname "$1")
  while [ "$d" != "$PROJECT" ] && [ "$d" != "." ] && [ "$d" != "/" ]; do
    [ -e "$d/.gdignore" ] && return 0
    d=$(dirname "$d")
  done
  return 1
}

HARNESSES=()
while IFS= read -r f; do
  gdignored "$f" || HARNESSES+=("res://${f#"$PROJECT"/}")
done < <(find "$PROJECT" \( -path "$PROJECT/.godot" -o -path "$PROJECT/addons" -o -name .git \) -prune \
           -o -type f -name 'diag_*.tscn' -print | sort)

RESULTS=() failed=() n=0 IMPORT=()
run() {  # run <kind> <res path> <banner>
  local kind="$1" scene="$2" banner="$3"
  local log="$OUT/$(printf '%s' "${scene#res://}" | tr '/' '_').log"
  n=$((n + 1))
  echo "== $kind $scene"
  bash "$RUNNER" --path "$PROJECT" --banner "$banner" --log "$log" ${IMPORT[@]+"${IMPORT[@]}"} \
    ${RUNARGS[@]+"${RUNARGS[@]}"} "$scene" > "$OUT/runner.out" 2>&1
  local rc=$?    # straight after the runner - anything in between would overwrite it with its own status
  # The first run imports (a fresh clone has no .godot/ cache); every later run reuses that cache.
  IMPORT=(--no-import)
  sed 's/^/   /' "$OUT/runner.out"
  if [ $rc -eq 3 ]; then echo "GODOT-CI: NO-ENGINE (set GODOT_BIN to the Godot 4 executable)"; exit 3; fi
  if [ $rc -eq 0 ]; then RESULTS+=("PASS  $kind  $scene")
  else RESULTS+=("FAIL  $kind  $scene"); failed+=("$scene"); fi
}

if [ -f "$PROJECT/${GATE#res://}" ]; then
  run gate "$GATE" '^PARSE-GATE: PASS'
else
  RESULTS+=("FAIL  gate  $GATE (missing - scaffold it with the godot-headless-harness skill)"); failed+=("$GATE")
  n=$((n + 1))
fi
for h in ${HARNESSES[@]+"${HARNESSES[@]}"}; do
  name=$(basename "$h" .tscn); name="${name#diag_}"
  run diag "$h" "^DIAG-$(printf '%s' "$name" | tr 'a-z' 'A-Z'): PASS"
done

echo "== summary (logs in $(show_path "$OUT"))"
printf '   %s\n' "${RESULTS[@]}"
nh=${#HARNESSES[@]}
why=""
[ ${#failed[@]} -gt 0 ] && why="${#failed[@]} of $n runs failed: ${failed[*]}"
if [ "$nh" -lt "$MIN_H" ]; then
  why="${why:+$why; }found $nh diag harness(es), --min-harnesses $MIN_H"
fi
if [ -n "$why" ]; then echo "GODOT-CI: FAIL ($why)"; exit 1; fi
echo "GODOT-CI: PASS (parse gate + $nh/$nh diag harnesses)"
exit 0
