#!/usr/bin/env bash
# test_run.sh - run a Godot 4 project's GUT or gdUnit4 tests headless and judge the run by the framework's exit code,
# its JUnit XML and the traps measured on GUT 9.7.1 / gdUnit4 6.2.2 - never by "the process exited 0":
#   GUT exits 0 when a test file does not parse ("All tests passed!"), when a test file does not extend GutTest, when
#   the test directory does not exist or holds no tests ("Nothing was run."), and on a fresh clone before --import.
#   gdUnit4 exits 0 when the directory does not exist or is empty ("No test cases found"), and hangs forever in its
#   `debug>` prompt when run with -d and a test file does not parse.
#
#   bash test_run.sh --path <project> [--framework gut|gdunit] [--dir res://tests] [options]
#
#   --framework F     gut | gdunit (default: the one installed under addons/; both installed -> pass it)
#   --dir RES         test directory, repeatable (default for GUT: "dirs" of res://.gutconfig.json; gdUnit4 has no
#                     project-wide default, so pass it). It must exist: a missing directory is a FAIL, not "0 tests".
#   --min-tests N     FAIL unless at least N tests PASSED (default 1) - zero tests run is never a pass
#   --strict          also FAIL on pending/risky tests and on gdUnit4's exit 101 (warnings, e.g. orphan nodes)
#   --no-import       skip the import (only when the .godot/ cache is current)
#   --timeout S       wall-clock backstop (default 300); --frames N (default 100000: the wall clock is the backstop)
#   --out DIR         where the log and the JUnit XML go (default: a fresh temp dir). Never inside the project:
#                     gdUnit4 would otherwise write reports/report_N into it on every run.
#
# Last line and exit code:
#   GODOT-TEST: PASS (<framework>: n passed, ...)   0
#   GODOT-TEST: FAIL (<reasons>)                    1
#   GODOT-TEST: NO-ENGINE                           3
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

PROJECT="" FW="" DIRS=() MIN=1 STRICT=0 DO_IMPORT=1 TIMEOUT_S=300 FRAMES=100000 OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PROJECT="${2%/}"; shift 2 ;;
    --framework) FW="$2"; shift 2 ;;
    --dir) DIRS+=("$2"); shift 2 ;;
    --min-tests) MIN="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --no-import) DO_IMPORT=0; shift ;;
    --timeout) TIMEOUT_S="$2"; shift 2 ;;
    --frames) FRAMES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "GODOT-TEST: FAIL (unknown argument '$1')"; exit 1 ;;
  esac
done
fail() { echo "GODOT-TEST: FAIL ($1)"; exit 1; }
[ -n "$PROJECT" ] && [ -f "$PROJECT/project.godot" ] || fail "no project.godot in --path '$PROJECT'"

RUNNER="$HERE/godot_run.sh"
[ -f "$RUNNER" ] || RUNNER="$HERE/../godot-run/godot_run.sh"
[ -f "$RUNNER" ] || fail "godot_run.sh not found next to test_run.sh or in ../godot-run/"

GUT_TOOL="addons/gut/gut_cmdln.gd" GDU_TOOL="addons/gdUnit4/bin/GdUnitCmdTool.gd"
if [ -z "$FW" ]; then
  [ -f "$PROJECT/$GUT_TOOL" ] && FW=gut
  if [ -f "$PROJECT/$GDU_TOOL" ]; then
    [ -n "$FW" ] && fail "both GUT and gdUnit4 are installed - pass --framework gut|gdunit"
    FW=gdunit
  fi
  [ -n "$FW" ] || fail "neither GUT (res://$GUT_TOOL) nor gdUnit4 (res://$GDU_TOOL) is installed"
fi
case "$FW" in
  gut) [ -f "$PROJECT/$GUT_TOOL" ] || fail "--framework gut, but res://$GUT_TOOL is missing" ;;
  gdunit) [ -f "$PROJECT/$GDU_TOOL" ] || fail "--framework gdunit, but res://$GDU_TOOL is missing" ;;
  *) fail "--framework must be gut or gdunit, got '$FW'" ;;
esac

if [ ${#DIRS[@]} -eq 0 ] && [ "$FW" = gut ] && [ -f "$PROJECT/.gutconfig.json" ]; then
  # "dirs": ["res://test/unit", "res://test/integration"]  (one line or several)
  while IFS= read -r d; do DIRS+=("$d"); done < <(tr -d '\r\n' < "$PROJECT/.gutconfig.json" \
    | sed -n 's/.*"dirs"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' | grep -o '"res://[^"]*"' | tr -d '"')
fi
[ ${#DIRS[@]} -gt 0 ] || fail "no test directory: pass --dir res://<dir> (GUT also reads \"dirs\" from res://.gutconfig.json)"
for d in "${DIRS[@]}"; do
  case "$d" in res://*) ;; *) fail "--dir must be a res:// path, got '$d'" ;; esac
  [ -d "$PROJECT/${d#res://}" ] || fail "test directory $d does not exist (both frameworks call that 0 tests and exit 0)"
done

[ -n "$OUT" ] || OUT=$(mktemp -d "${TMPDIR:-/tmp}/godot_test.XXXXXX")
mkdir -p "$OUT"
engine_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
OUT_E=$(engine_path "$OUT")

if [ "$DO_IMPORT" = 1 ]; then
  # GUT and gdUnit4 are class_name-based: on a fresh clone nothing resolves until --import (GUT then exits 0).
  bash "$RUNNER" --path "$PROJECT" --import-only > "$OUT/import.runner" 2>&1
  rc=$?
  [ $rc -eq 3 ] && { cat "$OUT/import.runner"; echo "GODOT-TEST: NO-ENGINE (set GODOT_BIN to the Godot 4 executable)"; exit 3; }
  [ $rc -eq 0 ] || { sed 's/^/   /' "$OUT/import.runner"; fail "import"; }
fi

ARGS=()
if [ "$FW" = gut ]; then
  XML="$OUT/junit.xml"
  ARGS=(-s "res://$GUT_TOOL")
  for d in "${DIRS[@]}"; do ARGS+=("-gdir=$d"); done
  # -gexit always: do not depend on GUT ending a headless run on its own.
  ARGS+=(-gexit -gdisable_colors "-gjunit_xml_file=$OUT_E/junit.xml")
else
  # Never -d: with a test file that does not parse it hung at `debug>` on Windows and exited 0 on Linux.
  # --ignoreHeadlessMode: without it gdUnit4 refuses headless (exit 103).
  # -rd user://...: reports outside the project. gdUnit4 turns any path starting with "/" into res://, so a Linux
  # absolute path would land INSIDE the project; user:// lands in the runner's isolated home, kept in $OUT/home.
  ARGS=(-s "res://$GDU_TOOL")
  for d in "${DIRS[@]}"; do ARGS+=(-a "$d"); done
  ARGS+=(--ignoreHeadlessMode -c -rd "user://gdunit-reports" -rc 1)
fi

# The runner gives isolation, --quit-after and the wall-clock timeout. Its ERROR-line rule is switched off: a passing
# test that EXPECTS an error (assert_push_error / assert_error(...).is_push_error) logs "ERROR: ..." too.
bash "$RUNNER" --path "$PROJECT" --no-import --allow-engine-errors --log "$OUT/test.log" --timeout "$TIMEOUT_S" \
  --frames "$FRAMES" --home "$OUT/home" "${ARGS[@]}" > "$OUT/runner.out" 2>&1
rrc=$?
[ $rrc -eq 3 ] && { cat "$OUT/runner.out"; echo "GODOT-TEST: NO-ENGINE (set GODOT_BIN to the Godot 4 executable)"; exit 3; }
code=$(sed -n 's/^run:[[:space:]]*exit \([0-9]*\),.*/\1/p' "$OUT/runner.out" | head -1)
CLEAN="$OUT/test.clean.log"
tr -d '\r' < "$OUT/test.log" | sed 's/\x1b\[[0-9;]*m//g' > "$CLEAN"

why=()
grep -q 'wall-clock timeout' "$OUT/runner.out" && why+=("wall-clock timeout ${TIMEOUT_S}s")
if grep -qE 'Parse Error|Compile Error' "$CLEAN"; then
  broken=$(grep -oE 'Failed to load script "res://[^"]+"|GDScript::reload \(res://[^:)]+' "$CLEAN" | grep -oE 'res://[^":)]+' \
    | sort -u | head -3 | tr '\n' ' ')
  why+=("a script does not compile: ${broken:-see log}")
fi
if [ "$FW" = gut ]; then
  [ "${code:-x}" = 0 ] || why+=("GUT exit ${code:-?}")
  grep -q 'class_names have not been imported' "$CLEAN" && why+=("GUT classes not imported (run without --no-import)")
  grep -q 'does not extend GutTest' "$CLEAN" && why+=("ignored test file(s): $(grep -oE 'Ignoring script [^ ]+' "$CLEAN" | sed 's/Ignoring script //' | tr '\n' ' ')")
  grep -q '\[GUT ERROR\]' "$CLEAN" && why+=("$(grep -m1 '\[GUT ERROR\]' "$CLEAN" | sed 's/.*\[GUT ERROR\]:[[:space:]]*//')")
else
  XML=$(find "$OUT/home" -path '*gdunit-reports*' -name results.xml 2>/dev/null | head -1)
  case "${code:-x}" in
    0) ;;
    101) [ $STRICT = 1 ] && why+=("gdUnit4 exit 101: warnings (e.g. orphan nodes) under --strict") ;;
    100) why+=("gdUnit4 exit 100: failing tests") ;;
    103) why+=("gdUnit4 exit 103: headless mode refused") ;;
    105) why+=("gdUnit4 exit 105: script errors detected") ;;
    *) why+=("gdUnit4 exit ${code:-?}") ;;
  esac
  grep -q 'No test cases found' "$CLEAN" && why+=("gdUnit4: no test cases found")
fi

total=0 passed=0 failed=0 skipped=0 risky=0
if [ -n "${XML:-}" ] && [ -f "$XML" ]; then
  # One tag per line, then count testcases: failure/error child -> failed, skipped child -> skipped, GUT status other
  # than "pass" (risky: no assert) -> risky, otherwise passed.
  read -r total passed failed skipped risky < <(tr '\n' ' ' < "$XML" | sed 's/</\n</g' | awk '
    function done_case() { if (!open) return; if (bad) f++; else if (skp) s++; else if (st != "" && st != "pass") r++; else p++; open = 0 }
    /^<testcase[ >]/ { done_case(); open = 1; bad = 0; skp = 0; st = ""; t++
                       if (match($0, /status="[^"]*"/)) st = substr($0, RSTART + 8, RLENGTH - 9)
                       if ($0 ~ /\/>[ \t]*$/) done_case() }
    /^<(failure|error)[ >]/ { if (open) bad = 1 }
    /^<skipped[ >]/ { if (open) skp = 1 }
    /^<\/testcase>/ { done_case() }
    END { done_case(); print t + 0, p + 0, f + 0, s + 0, r + 0 }')
else
  why+=("no JUnit XML written - the run did not complete, or found nothing to run")
fi
[ "$failed" -gt 0 ] && why+=("$failed failing test(s)")
[ "$passed" -lt "$MIN" ] && why+=("$passed test(s) passed, --min-tests $MIN")
[ $STRICT = 1 ] && [ $((skipped + risky)) -gt 0 ] && why+=("$skipped pending/skipped and $risky risky test(s) under --strict")

echo "test:    $FW, dirs ${DIRS[*]}, log $(engine_path "$OUT/test.log")${XML:+, xml $(engine_path "$XML")}"
grep -nE 'FAIL|Failed|failed|ERROR|Parse Error|Ignoring script|Nothing was run|No test cases|Exit code|passed\.|Statistics|Overall Summary' "$CLEAN" \
  | grep -vE 'Disabled fail fast|0 failures \|' | head -30 | sed 's/^/  | /'
summary="$FW: $passed passed, $failed failed, $skipped pending/skipped, $risky risky (of $total)"
if [ ${#why[@]} -gt 0 ]; then
  msg=$(printf '%s; ' "${why[@]}"); echo "GODOT-TEST: FAIL (${msg%; } | $summary)"; exit 1
fi
note=""; [ "$FW" = gdunit ] && [ "${code:-}" = 101 ] && note=", gdUnit4 warnings (exit 101)"
echo "GODOT-TEST: PASS ($summary$note)"
exit 0
