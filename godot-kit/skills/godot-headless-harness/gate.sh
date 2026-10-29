#!/usr/bin/env bash
# gate.sh - does every GDScript in a Godot 4 project compile? Runs the project's own parse gate scene when it has one,
# else parse_gate_script.gd from this directory as `--script` - no file is added to the project either way.
#
#   bash gate.sh --path <project> [options]
#
#   --gate RES      the project's gate scene (default res://tools/ci/parse_gate.tscn; used only if it exists)
#   --script-gate   use parse_gate_script.gd even when the project has a gate scene
#   --min N         script-gate only: fewer scripts than N fails (default 1)
#   --skip RES      script-gate only: a res:// directory to leave out, repeatable (res://addons always is). Anything
#                   else (a bare `src`, a typo'd --min) FAILS the gate instead of being ignored.
#   --include RES   script-gate only: check this res:// directory although it lies under a skipped one, repeatable -
#                   the add-on you are writing (`--include res://addons/my_tool`); other add-ons stay skipped. A
#                   directory that does not exist FAILS. With a gate scene, take the directory out of its SKIP instead.
#   --debug         run the gate with --debug, so the engine prints its GDScript warnings (see warnings.sh, which
#                   only does this after a plain gate passed: with --debug a parse error can hang the engine)
#   --timeout S, --no-import, --log FILE   passed to the runner
#
# Last line and exit code: the runner's (GODOT-RUN: PASS 0 / FAIL 1 / NO-ENGINE 3), banner `PARSE-GATE: PASS`.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

PROJECT="" GATE="res://tools/ci/parse_gate.tscn" FORCE_SCRIPT=0 DEBUG=0 INCLUDE=0 USER_ARGS=() RUNARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PROJECT="${2%/}"; shift 2 ;;
    --gate) GATE="$2"; shift 2 ;;
    --script-gate) FORCE_SCRIPT=1; shift ;;
    --min) USER_ARGS+=(--min="$2"); shift 2 ;;
    --skip) USER_ARGS+=(--skip="$2"); shift 2 ;;
    --include) USER_ARGS+=(--include="$2"); INCLUDE=1; shift 2 ;;
    --debug) DEBUG=1; shift ;;
    --timeout|--log) RUNARGS+=("$1" "$2"); shift 2 ;;
    --no-import) RUNARGS+=("$1"); shift ;;
    *) echo "GODOT-RUN: FAIL (gate.sh: unknown argument '$1')"; exit 1 ;;
  esac
done
[ -n "$PROJECT" ] && [ -f "$PROJECT/project.godot" ] || { echo "GODOT-RUN: FAIL (no project.godot in --path '$PROJECT')"; exit 1; }

RUNNER="$HERE/godot_run.sh"
[ -f "$RUNNER" ] || RUNNER="$HERE/../godot-run/godot_run.sh"
[ -f "$RUNNER" ] || { echo "GODOT-RUN: FAIL (godot_run.sh not found next to gate.sh or in ../godot-run/)"; exit 1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

DBG=(); [ "$DEBUG" = 1 ] && DBG=(--debug)
if [ "$FORCE_SCRIPT" = 0 ] && [ -f "$PROJECT/${GATE#res://}" ]; then
  echo "gate:    the project's $GATE"
  # Ignored here, --include would look like a check of the add-on that never happened.
  [ "$INCLUDE" = 1 ] && { echo "GODOT-RUN: FAIL (gate.sh: --include needs the script gate - add --script-gate, or take the directory out of the scene's SKIP)"; exit 1; }
  [ ${#USER_ARGS[@]} -gt 0 ] && echo "gate:    note: --min/--skip apply to the script gate only; the scene has its own MIN_SCRIPTS/SKIP"
  exec bash "$RUNNER" --path "$PROJECT" --banner '^PARSE-GATE: PASS' ${RUNARGS[@]+"${RUNARGS[@]}"} -- \
    ${DBG[@]+"${DBG[@]}"} "$GATE"
fi
why="the project has no gate scene at $GATE"; [ "$FORCE_SCRIPT" = 1 ] && why="--script-gate"
echo "gate:    parse_gate_script.gd from the skill ($why)"
exec bash "$RUNNER" --path "$PROJECT" --banner '^PARSE-GATE: PASS' ${RUNARGS[@]+"${RUNARGS[@]}"} -- \
  ${DBG[@]+"${DBG[@]}"} --script "$(native "$HERE/parse_gate_script.gd")" ++ ${USER_ARGS[@]+"${USER_ARGS[@]}"}
