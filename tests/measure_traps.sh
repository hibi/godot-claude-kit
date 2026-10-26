#!/usr/bin/env bash
# Reproduces every trap the skills warn about, on the demo project, and prints what the engine actually did.
#
#   GODOT_BIN=/path/to/godot bash tests/measure_traps.sh
#
# Each trap copies ONE broken fixture from tests/sabotage/ into the demo, runs the engine, records exit code and the
# lines that matter, then removes the fixture again - so the demo is always clean before and after.
# Engine runs use a throwaway APPDATA/HOME so nothing touches your real Godot editor settings.
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)
DEMO="$ROOT/demo"
FIX="$ROOT/tests/sabotage"
: "${GODOT_BIN:=godot}"
WORK="${TMPDIR:-${TEMP:-/tmp}}/gck_traps"
# T15 swaps a REAL demo file; if an earlier run was killed mid-T15, its backup is about to be wiped - stop first.
if cmp -s "$FIX/health_no_clamp.gd" "$DEMO/src/health.gd"; then
  echo "demo/src/health.gd is still the sabotaged copy from an interrupted run - restore it before measuring"; exit 1
fi
rm -rf "$WORK"; mkdir -p "$WORK/home" "$WORK/logs"
export APPDATA="$WORK/home" LOCALAPPDATA="$WORK/home" HOME="$WORK/home" XDG_DATA_HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home"

# Never leave a fixture behind, even on Ctrl+C.
cleanup() {
  rm -f "$DEMO/src/_sabotage.gd" "$DEMO/tools/_trap.gd" "$DEMO/tools/_trap.tscn" "$DEMO/src/_sabotage.gd.uid" "$DEMO/tools/_trap.gd.uid"
  # T15 replaces a REAL demo file; put the original back.
  if [ -f "$WORK/health.gd.orig" ]; then cp "$WORK/health.gd.orig" "$DEMO/src/health.gd"; rm -f "$WORK/health.gd.orig"; fi
}
trap cleanup EXIT

godot() { "$GODOT_BIN" "$@"; }
import() { godot --headless --import --path "$DEMO" > "$WORK/logs/import.log" 2>&1; }
show() {  # show <label> <exit> <log>
  printf '\n=== %s\n    exit=%s\n' "$1" "$2"
  grep -E 'SCRIPT ERROR|Parse Error|Compile Error|ERROR|FAIL|PASS|ok  ' "$3" | sed 's/^/    | /' | head -8
  [ -s "$3" ] || echo "    | (empty output)"
}
scene_wrap() {  # writes demo/tools/_trap.tscn pointing at demo/tools/_trap.gd
  printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://tools/_trap.gd" id="1"]\n\n[node name="Trap" type="Node"]\nscript = ExtResource("1")\n' > "$DEMO/tools/_trap.tscn"
}

echo "engine: $("$GODOT_BIN" --version 2>/dev/null)"
cleanup; import; echo "clean import exit=$?"

# T0 - the clean demo: the gate and the example harness must be green.
godot --headless --path "$DEMO" res://tools/ci/parse_gate.tscn > "$WORK/logs/t0_gate.log" 2>&1; show "T0a parse gate on the CLEAN demo" $? "$WORK/logs/t0_gate.log"
godot --headless --path "$DEMO" res://tools/diag_health.tscn > "$WORK/logs/t0_diag.log" 2>&1; show "T0b diag_health on the CLEAN demo" $? "$WORK/logs/t0_diag.log"

# T1/T2 - `--import` is not a parse gate: syntax error and Vector2.z.
for f in syntax_error vector2_z; do
  cp "$FIX/$f.gd" "$DEMO/src/_sabotage.gd"
  import; show "T1 --import with src/_sabotage.gd = $f" $? "$WORK/logs/import.log"
  cp "$WORK/logs/import.log" "$WORK/logs/t1_import_$f.log"
  godot --headless --path "$DEMO" --check-only --script res://src/_sabotage.gd > "$WORK/logs/t2_check_$f.log" 2>&1
  show "T2 --check-only on $f" $? "$WORK/logs/t2_check_$f.log"
  godot --headless --path "$DEMO" res://tools/ci/parse_gate.tscn > "$WORK/logs/t3_gate_$f.log" 2>&1
  show "T3 parse gate with $f" $? "$WORK/logs/t3_gate_$f.log"
  rm -f "$DEMO/src/_sabotage.gd" "$DEMO/src/_sabotage.gd.uid"
done
import

# T4 - --check-only false positive on a CORRECT script that names an autoload.
godot --headless --path "$DEMO" --check-only --script res://src/enemy.gd > "$WORK/logs/t4_check_autoload.log" 2>&1
show "T4 --check-only on the correct src/enemy.gd (uses autoload GameState)" $? "$WORK/logs/t4_check_autoload.log"

# T5 - --user-data-dir on a headless SCENE run.
godot --headless --path "$DEMO" --quit-after 600 --user-data-dir "$WORK/udd" res://tools/diag_health.tscn > "$WORK/logs/t5_udd_scene.log" 2>&1
show "T5 diag_health WITH --user-data-dir (--quit-after 600 backstop)" $? "$WORK/logs/t5_udd_scene.log"

# T6 - an async check called without await.
cp "$FIX/unawaited_check.gd" "$DEMO/tools/_trap.gd"; scene_wrap; import
godot --headless --path "$DEMO" --quit-after 600 res://tools/_trap.tscn > "$WORK/logs/t6_unawaited.log" 2>&1
show "T6 harness with an un-awaited async check" $? "$WORK/logs/t6_unawaited.log"

# T7 - a harness whose own script fails to parse.
cp "$FIX/broken_harness.gd" "$DEMO/tools/_trap.gd"; import
godot --headless --path "$DEMO" --quit-after 600 res://tools/_trap.tscn > "$WORK/logs/t7_broken_harness.log" 2>&1
show "T7 harness scene whose script does not parse (--quit-after 600)" $? "$WORK/logs/t7_broken_harness.log"

# T16 - a SLOW async check (timer) called without await: with no coverage count, and with one.
for f in unawaited_slow unawaited_slow_counted; do
  cp "$FIX/$f.gd" "$DEMO/tools/_trap.gd"; import
  godot --headless --path "$DEMO" --quit-after 600 res://tools/_trap.tscn > "$WORK/logs/t16_$f.log" 2>&1
  show "T16 un-awaited slow check, $f" $? "$WORK/logs/t16_$f.log"
done
cleanup; import

# T15 - does the example harness bite? Break the code under test (Health.damage stops clamping), then restore it.
cp "$DEMO/src/health.gd" "$WORK/health.gd.orig"; cp "$FIX/health_no_clamp.gd" "$DEMO/src/health.gd"
godot --headless --path "$DEMO" --quit-after 600 res://tools/diag_health.tscn > "$WORK/logs/t15_health_no_clamp.log" 2>&1
show "T15 diag_health with Health.damage sabotaged (expect one FAIL)" $? "$WORK/logs/t15_health_no_clamp.log"
cleanup
godot --headless --path "$DEMO" --quit-after 600 res://tools/diag_health.tscn > "$WORK/logs/t15_restored.log" 2>&1
show "T15 the same after restoring health.gd (expect PASS)" $? "$WORK/logs/t15_restored.log"

# T8 - --quit-after counts FRAMES, not seconds: a run whose scene never loads (T5) burns the whole count.
for n in 60 600; do
  s=$(date +%s%N)
  godot --headless --path "$DEMO" --quit-after $n --user-data-dir "$WORK/udd" res://tools/diag_health.tscn > "$WORK/logs/t8_quit_$n.log" 2>&1
  e=$?; t=$(date +%s%N)
  printf '\n=== T8 never-loading run with --quit-after %s\n    exit=%s wall=%sms\n' "$n" "$e" "$(( (t - s) / 1000000 ))"
done

# T11 - a quiet but HEALTHY scene vs the never-loading run of T8: is there any difference in the log?
godot --headless --path "$DEMO" --quit-after 60 res://src/main.tscn > "$WORK/logs/t11_main_quiet.log" 2>&1
printf '\n=== T11 main.tscn (healthy, prints nothing) vs T8 (scene never ran)\n    exit=%s logs %s\n' "$?" \
  "$(cmp -s "$WORK/logs/t11_main_quiet.log" "$WORK/logs/t8_quit_60.log" && echo "BYTE-IDENTICAL" || echo "differ")"
printf '    lines end in CR: %s of %s\n' "$(grep -c $'\r$' "$WORK/logs/t0_diag.log")" "$(wc -l < "$WORK/logs/t0_diag.log")"

# T9 (Windows only) - the GUI build (no _console suffix): from this shell, and from PowerShell with `&`.
case "$GODOT_BIN" in *_console.exe)
  GUI_EXE="${GODOT_BIN%_console.exe}.exe"
  if [ -f "$GUI_EXE" ]; then
    "$GUI_EXE" --headless --path "$DEMO" --quit-after 600 res://tools/diag_health.tscn > "$WORK/logs/t9_gui_exe_bash.log" 2>&1
    show "T9 GUI exe (${GUI_EXE##*/}) from bash" $? "$WORK/logs/t9_gui_exe_bash.log"
    # ...and the failing direction: is a non-zero exit code propagated too?
    cp "$FIX/syntax_error.gd" "$DEMO/src/_sabotage.gd"; import
    "$GUI_EXE" --headless --path "$DEMO" --quit-after 600 res://tools/ci/parse_gate.tscn > "$WORK/logs/t9_gui_exe_bash_fail.log" 2>&1
    show "T9 GUI exe from bash, parse gate with syntax_error (expect exit 1)" $? "$WORK/logs/t9_gui_exe_bash_fail.log"
    rm -f "$DEMO/src/_sabotage.gd" "$DEMO/src/_sabotage.gd.uid"; import
  fi
  if [ -f "$GUI_EXE" ] && command -v powershell.exe >/dev/null; then
    ps_log="$WORK/logs/t9_gui_exe_ps.log"
    # Count and wait only for the engine THIS step started: other runs of the same exe (an editor, another project's
    # tool) must neither inflate still_running nor make this step wait for them - it once waited on a foreign run.
    powershell.exe -NoProfile -Command "\$exe='$(cygpath -w "$GUI_EXE")'; \$before=@(Get-Process | Where-Object { \$_.Path -eq \$exe } | ForEach-Object { \$_.Id }); \$sw=[Diagnostics.Stopwatch]::StartNew(); & \$exe --headless --path '$(cygpath -w "$DEMO")' --quit-after 600 res://tools/diag_health.tscn *> '$(cygpath -w "$WORK/logs/t9_raw.log")'; \$ms=\$sw.ElapsedMilliseconds; \$mine=@(Get-Process | Where-Object { \$_.Path -eq \$exe -and \$before -notcontains \$_.Id }); \"returned_ms=\$ms exit='\$LASTEXITCODE' still_running=\$(\$mine.Count)\"; \$mine | Wait-Process -Timeout 60 -ErrorAction SilentlyContinue" > "$ps_log" 2>&1
    printf '\n=== T9 GUI exe (%s) from PowerShell with &\n    %s\n    log bytes=%s\n' "${GUI_EXE##*/}" "$(tr -d '\r' < "$ps_log")" "$(wc -c < "$WORK/logs/t9_raw.log")"
  fi
esac

# T10 - a fresh clone (no .godot/ cache) run WITHOUT --import first: class_name types are not registered yet.
rm -rf "$WORK/clone"; cp -r "$DEMO" "$WORK/clone"; rm -rf "$WORK/clone/.godot"
godot --headless --path "$WORK/clone" --quit-after 600 res://tools/diag_health.tscn > "$WORK/logs/t10_no_import.log" 2>&1
show "T10 diag_health on a fresh clone without --import" $? "$WORK/logs/t10_no_import.log"
godot --headless --path "$WORK/clone" --import > "$WORK/logs/t10_import.log" 2>&1
godot --headless --path "$WORK/clone" --quit-after 600 res://tools/diag_health.tscn > "$WORK/logs/t10_after_import.log" 2>&1
show "T10 the same clone after --import" $? "$WORK/logs/t10_after_import.log"

# T13 (Windows only) - Windows PowerShell 5.1 `*>` on a run whose stderr carries a SCRIPT ERROR.
if command -v powershell.exe >/dev/null; then
  cp "$FIX/syntax_error.gd" "$DEMO/src/_sabotage.gd"; import
  ps13="$(cygpath -w "$WORK/logs/t13_ps_redirect.log")"
  powershell.exe -NoProfile -Command "& '$(cygpath -w "$GODOT_BIN")' --headless --path '$(cygpath -w "$DEMO")' --quit-after 600 res://tools/ci/parse_gate.tscn *> '$ps13'" > /dev/null 2>&1
  raw="$WORK/logs/t13_ps_redirect.log"; dec="$WORK/logs/t13_ps_redirect.decoded.log"
  tr -d '\000\r' < "$raw" > "$dec"   # crude UTF-16LE -> ASCII, enough for the engine's ASCII output
  printf '\n=== T13 PowerShell 5.1 *> redirect with a SCRIPT ERROR on stderr\n'
  printf '    file starts with UTF-16LE BOM: %s; grep SCRIPT ERROR on the raw file: %s match(es)\n' \
    "$(head -c2 "$raw" | od -An -tx1 | tr -d ' \n' | grep -q '^fffe' && echo yes || echo no)" "$(grep -c 'SCRIPT ERROR' "$raw")"
  printf '    decoded: lines starting with ERROR: = %s, NativeCommandError records = %s, SCRIPT ERROR lines = %s\n' \
    "$(grep -c '^ERROR:' "$dec")" "$(grep -c 'NativeCommandError' "$dec")" "$(grep -c 'SCRIPT ERROR' "$dec")"
  grep -m1 'SCRIPT ERROR' "$dec" | sed 's/^/    | /'
  # The remedy the skill recommends: Start-Process -Wait into separate stdout/stderr files, console AND GUI build.
  for exe in "$GODOT_BIN" "${GODOT_BIN%_console.exe}.exe"; do
    [ -f "$exe" ] || continue
    tag=$(basename "$exe" .exe); o="$WORK/logs/t13_sp_$tag.out"; e="$WORK/logs/t13_sp_$tag.err"
    code=$(powershell.exe -NoProfile -Command "\$p = Start-Process -FilePath '$(cygpath -w "$exe")' -ArgumentList '--headless','--path','$(cygpath -w "$DEMO")','--quit-after','600','res://tools/ci/parse_gate.tscn' -RedirectStandardOutput '$(cygpath -w "$o")' -RedirectStandardError '$(cygpath -w "$e")' -NoNewWindow -Wait -PassThru; \$p.ExitCode" | tr -d '\r')
    printf '    Start-Process -Wait, %s: ExitCode=%s (expect 1); raw grep ^ERROR: in .err = %s; FAIL lines in .out = %s; .err starts with UTF-16 BOM: %s\n' \
      "$tag" "$code" "$(grep -c '^ERROR:' "$e")" "$(grep -c '^ *FAIL ' "$o")" \
      "$(head -c2 "$e" | od -An -tx1 | tr -d ' \n' | grep -q '^fffe' && echo yes || echo no)"
  done
  rm -f "$DEMO/src/_sabotage.gd" "$DEMO/src/_sabotage.gd.uid"; import
fi

# T14 - coreutils `timeout` as a wall-clock backstop: exit code, and does the engine process die with it?
if command -v timeout >/dev/null; then
  timeout 5 "$GODOT_BIN" --headless --path "$DEMO" --quit-after 1000000 res://src/main.tscn > "$WORK/logs/t14_timeout.log" 2>&1
  e14=$?
  if command -v tasklist >/dev/null; then left=$(tasklist //FO CSV //NH | grep -ci "$(basename "$GODOT_BIN")")
  else left=$(pgrep -fc "$(basename "$GODOT_BIN")"); fi
  printf '\n=== T14 timeout 5 on a run that would last ~2 h\n    exit=%s, engine processes left=%s, ERROR: lines (teardown noise)=%s\n' \
    "$e14" "$left" "$(grep -c '^ERROR:' "$WORK/logs/t14_timeout.log")"
fi

# T12 - does the APPDATA/HOME redirect really move the engine's dirs? (This script's own isolation, checked.)
printf 'extends SceneTree\nfunc _init() -> void:\n\tprint("USERDATA=", OS.get_user_data_dir())\n\tprint("CONFIG=", OS.get_config_dir())\n\tquit()\n' > "$WORK/probe_dirs.gd"
godot --headless --path "$DEMO" --script "$WORK/probe_dirs.gd" > "$WORK/logs/t12_dirs.log" 2>&1
printf '\n=== T12 engine dirs under the redirect (expect both inside %s)\n' "$WORK/home"
tr -d '\r' < "$WORK/logs/t12_dirs.log" | grep '=' | sed 's/^/    | /'

# Kit consistency: the demo's gate is the skill template, differing only in its MIN_SCRIPTS floor.
tpl="$ROOT/skills/godot-headless-harness/templates/parse_gate.gd"
printf '\n=== KIT demo gate vs skill template (ignoring MIN_SCRIPTS): %s\n' \
  "$(diff <(grep -v '^const MIN_SCRIPTS' "$tpl") <(grep -v '^const MIN_SCRIPTS' "$DEMO/tools/ci/parse_gate.gd") > /dev/null && echo "in sync" || echo "DIFFERENT")"

# Kit: scaffold into a demo copy without tools/ and check what the skill promises, in both directions.
SK="$ROOT/skills/godot-headless-harness/scaffold.sh"; K="$WORK/kit"
rm -rf "$K"; cp -r "$DEMO" "$K"; rm -rf "$K/.godot" "$K/tools"
bash "$SK" --path "$K" gate > /dev/null; bash "$SK" --path "$K" harness probe > /dev/null
godot --headless --path "$K" --import > "$WORK/logs/kit_import.log" 2>&1
kit_run() {  # kit_run <label> <scene> <log>
  godot --headless --path "$K" --quit-after 600 "$2" > "$WORK/logs/$3" 2>&1; show "KIT $1" $? "$WORK/logs/$3"
}
kit_run "fresh scaffolded harness (expect FAIL: placeholder)" res://tools/diag_probe.tscn kit_fresh.log
# Replace the placeholder body with the template's own commented example, uncommented.
awk '
  /^func _check_placeholder\(\)/ { print; inbody = 1; next }
  inbody && /^\t#   / { sub(/^\t#   /, "\t"); sub(/[ ]+# .*$/, ""); print; next }
  inbody && /^\t#/ { next }
  inbody { next }
  { print }
' "$K/tools/diag_probe.gd" > "$K/tools/diag_probe.tmp" && mv "$K/tools/diag_probe.tmp" "$K/tools/diag_probe.gd"
kit_run "harness with the template example filled in (expect PASS 2/2)" res://tools/diag_probe.tscn kit_filled.log
mkdir -p "$K/addons/thirdparty" "$K/fixtures" "$K/src/broken"; touch "$K/fixtures/.gdignore"
cp "$FIX/syntax_error.gd" "$K/addons/thirdparty/bad.gd"; cp "$FIX/syntax_error.gd" "$K/fixtures/bad.gd"
kit_run "gate with broken scripts only in addons/ and a .gdignore dir (expect PASS)" res://tools/ci/parse_gate.tscn kit_skip.log
cp "$FIX/syntax_error.gd" "$K/src/broken/bad.gd"
kit_run "gate with a broken script in src/ (expect FAIL)" res://tools/ci/parse_gate.tscn kit_broken.log

# Kit: godot-ci on fresh demo copies (no .godot/), one sabotage at a time. A verdict that ignores a failed run once
# slipped through here (rc read after another command), so every direction is checked on every measurement.
CI="$ROOT/skills/godot-ci/ci.sh"; C="$WORK/ci"
ci_case() {  # ci_case <label> <setup command, run inside the copy> [ci.sh args...]
  local label="$1" setup="$2"; shift 2
  rm -rf "$C"; cp -r "$DEMO" "$C"; rm -rf "$C/.godot"
  (cd "$C" && eval "$setup")
  GODOT_BIN="$GODOT_BIN" bash "$CI" --path "$C" --out "$WORK/logs/ci_$(printf '%s' "$label" | tr -c 'a-z0-9' _)" "$@" \
    > "$WORK/logs/ci.out" 2>&1
  printf '\n=== KIT ci.sh: %s\n    exit=%s\n' "$label" $?
  grep -E '^   (PASS|FAIL)  |^GODOT-CI' "$WORK/logs/ci.out" | sed 's/^ */    | /'
}
ci_case "clean demo (expect PASS)" ":"
ci_case "syntax error in src/ (expect FAIL: gate)" "cp '$FIX/syntax_error.gd' src/_sabotage.gd"
ci_case "Health clamp removed (expect FAIL: diag_health)" "cp '$FIX/health_no_clamp.gd' src/health.gd"
ci_case "gate scene missing (expect PASS via the kit script gate)" "rm tools/ci/parse_gate.tscn tools/ci/parse_gate.gd"
ci_case "gate scene missing + syntax error in src/ (expect FAIL: script gate)" \
  "rm tools/ci/parse_gate.tscn tools/ci/parse_gate.gd; cp '$FIX/syntax_error.gd' src/_sabotage.gd"
ci_case "--gate naming a missing scene (expect FAIL: gate, no fallback)" ":" --gate res://tools/ci/nope.tscn
ci_case "--min-harnesses 3 with two harnesses (expect FAIL)" ":" --min-harnesses 3

# Kit: `ci.sh install` into a git repo whose Godot project sits in game/. The workflow must point at game/ (a path
# comparison once produced a bogus absolute-ish path on Git Bash, where /tmp and %TEMP% are one directory), and the
# vendored copy must pass on its own.
if command -v git > /dev/null; then
  G="$WORK/ci_repo"; rm -rf "$G"; mkdir -p "$G"; cp -r "$DEMO" "$G/game"; rm -rf "$G/game/.godot"; git -C "$G" init -q
  GODOT_BIN="$GODOT_BIN" bash "$CI" --path "$G/game" install > "$WORK/logs/ci_install.out" 2>&1
  printf '\n=== KIT ci.sh install, project in game/ of a git repo (expect --path "game", vendored copy PASS)\n    exit=%s\n' $?
  grep -E 'run: bash' "$G/.github/workflows/godot-ci.yml" | sed 's/^ */    | /'
  (cd "$G" && GODOT_BIN="$GODOT_BIN" bash game/tools/ci/ci.sh --path game 2>&1 | tail -1 | sed 's/^/    | /')
  printf '    (shots step in the workflow: %s)\n' "$(grep -c 'Virtual display' "$G/.github/workflows/godot-ci.yml")"
  # No gate scene + --shot-dir: the vendored script gate (inside res:// - re-loading itself crashed the engine before
  # it skipped itself) and the workflow's xvfb step + shot options.
  G="$WORK/ci_repo2"; rm -rf "$G"; mkdir -p "$G"; cp -r "$DEMO" "$G/game"; rm -rf "$G/game/.godot"; git -C "$G" init -q
  rm "$G/game/tools/ci/parse_gate.tscn" "$G/game/tools/ci/parse_gate.gd"
  GODOT_BIN="$GODOT_BIN" bash "$CI" --path "$G/game" install --shot-dir res://tests/shots > "$WORK/logs/ci_install2.out" 2>&1
  printf '\n=== KIT ci.sh install --shot-dir, no gate scene (expect shots step + options, vendored script gate PASS)\n    exit=%s\n' $?
  grep -E 'run: bash|name: Virtual display' "$G/.github/workflows/godot-ci.yml" | sed 's/^ */    | /'
  (cd "$G" && GODOT_BIN="$GODOT_BIN" bash game/tools/ci/ci.sh --path game 2>&1 | grep -E '^   (PASS|FAIL)  gate|^GODOT-CI' \
    | sed 's/^ */    | /')
else
  printf '\n=== KIT ci.sh install: SKIPPED (no git on this machine)\n'
fi

# ---------------------------------------------------------------------------------------------------------------------
# Multiplayer (ENet, loopback). N1-N7 run tests/sabotage/net_probe.gd as a --script in a demo copy; the KIT net cases
# run the demo's two-process harness through net_run.sh, one sabotage at a time.
NETC="$WORK/net"; rm -rf "$NETC"; cp -r "$DEMO" "$NETC"; rm -rf "$NETC/.godot"
cp "$FIX/net_probe.gd" "$NETC/_net_probe.gd"; cp "$FIX/hold_udp_port.gd" "$NETC/_hold_udp_port.gd"
godot --headless --path "$NETC" --import > "$WORK/logs/net_import.log" 2>&1
NP=$((30000 + RANDOM % 20000))
now_ms() { echo $(( $(date +%s%N) / 1000000 )); }
probe() {  # probe <log> <seconds> <user args...>: one probe process, bounded by timeout
  local log="$1" s="$2"; shift 2
  timeout "$s" "$GODOT_BIN" --headless --path "$NETC" --script res://_net_probe.gd -- "$@" > "$WORK/logs/$log" 2>&1
}
nshow() {  # nshow <label> <log...>: the probe's own lines and every ERROR, per log
  printf '\n=== %s\n' "$1"; shift
  for l in "$@"; do
    echo "    -- $l"
    tr -d '\r' < "$WORK/logs/$l" | grep -E '^\[|^ERROR|^SCRIPT ERROR|exit=' | grep -v 'Unreferenced static|RID allocations|PagedAllocator' \
      | sed 's/^/    | /' | head -12
  done
}
engines_left() {
  if command -v tasklist >/dev/null; then tasklist //FO CSV //NH | grep -ci "$(basename "$GODOT_BIN")"
  else pgrep -fc "$(basename "$GODOT_BIN")"; fi
}

probe n1_busy.log 20 --role=busy --port=$NP; echo "exit=$?" >> "$WORK/logs/n1_busy.log"
nshow "N1 create_server twice on one port (one process)" n1_busy.log

probe n2_server.log 30 --role=server --port=$((NP + 1)) & sleep 1
probe n2_client.log 30 --role=client --port=$((NP + 1)); echo "exit=$?" >> "$WORK/logs/n2_client.log"; wait
echo "exit=(server, see above)" >> "$WORK/logs/n2_server.log"
nshow "N2 client calls .rpc() on a function WITHOUT @rpc, and rpc_id() with an unknown name" n2_client.log n2_server.log

probe n3_server.log 30 --role=server --port=$((NP + 2)) & sleep 1
probe n3_client.log 30 --role=client --port=$((NP + 2)) --root=ProbeElsewhere; echo "exit=$?" >> "$WORK/logs/n3_client.log"; wait
nshow "N3 server node /root/Probe, client node /root/ProbeElsewhere (same script)" n3_client.log n3_server.log

t=$(now_ms); probe n4_noserver.log 120 --role=noserver --port=$((NP + 3)); e=$?
nshow "N4 client, nobody listening (exit=$e, wall=$(( $(now_ms) - t )) ms)" n4_noserver.log

t=$(now_ms); probe n5_client.log 30 --role=client --port=$((NP + 4)) & sleep 2
probe n5_server.log 30 --role=server --port=$((NP + 4)); wait
nshow "N5 client started 2 s BEFORE the server (client timings are from its own start)" n5_client.log

probe n6_server.log 3 --role=server --port=$((NP + 5)) & sleep 1
probe n6_idle.log 60 --role=idle --port=$((NP + 5)); wait
nshow "N6 server killed by timeout 3 s while a client is connected (client started 1 s after it)" n6_idle.log
probe n7_busy.log 20 --role=busy --port=$((NP + 5))
nshow "N7 the same port right after that kill (first create_server: 0 = free)" n7_busy.log

# A plain script that calls .rpc() on a non-@rpc function compiles: the parse gate cannot see N2.
printf 'extends Node\n\nfunc not_an_rpc() -> void:\n\tpass\n\nfunc send() -> void:\n\tnot_an_rpc.rpc()\n\trpc_id(1, "no_such_method")\n' \
  > "$NETC/src/_sabotage.gd"
godot --headless --path "$NETC" --quit-after 600 res://tools/ci/parse_gate.tscn > "$WORK/logs/n_gate.log" 2>&1
show "N8 parse gate with a script calling .rpc() on a non-@rpc function and rpc_id() with an unknown name" $? \
  "$WORK/logs/n_gate.log"
rm -f "$NETC/src/_sabotage.gd"

NET="$ROOT/skills/godot-multiplayer-harness/net_run.sh"
net_case() {  # net_case <label> [net_run.sh args...] - runs the demo harness, prints per-role verdicts
  local label="$1"; shift
  local t; t=$(now_ms)
  GODOT_BIN="$GODOT_BIN" bash "$NET" --path "$NETC" --no-import "$@" res://tools/netdiag_hits.tscn > "$WORK/logs/net.out" 2>&1
  local e=$?
  printf '\n=== KIT net_run.sh: %s\n    exit=%s wall=%s ms engine processes left=%s\n' "$label" $e $(( $(now_ms) - t )) "$(engines_left)"
  grep -E '^== |GODOT-RUN|GODOT-NET|^ +\| +[0-9]+: *(FAIL|ERROR|SCRIPT)' "$WORK/logs/net.out" | sed 's/^ */    | /'
}
H="$NETC/tools/netdiag_hits.gd"; M="$NETC/src/net/net_match.gd"
cp "$H" "$WORK/netdiag_hits.orig"; cp "$M" "$WORK/net_match.orig"
net_case "clean demo (expect PASS)" --port $((NP + 10))
sed -i 's/^func _server() -> void:$/&\n\t_check("sabotage: server-side failure", false, "on purpose")/' "$H"
net_case "a FAIL on the server side only (expect server FAIL, client PASS, verdict FAIL)" --port $((NP + 11))
cp "$WORK/netdiag_hits.orig" "$H"
sed -i 's/^func _client() -> void:$/&\n\t_check("sabotage: client-side failure", false, "on purpose")/' "$H"
net_case "a FAIL on the client side only (expect client FAIL, server PASS, verdict FAIL)" --port $((NP + 12))
cp "$WORK/netdiag_hits.orig" "$H"
sed -i 's/^\tadd_child(_match)$/&\n\tif role == "client":\n\t\t_match.name = "NetMatchElsewhere"/' "$H"
net_case "client's NetMatch at another node path (expect FAIL)" --port $((NP + 13))
cp "$WORK/netdiag_hits.orig" "$H"
sed -i '/^@rpc("authority", "call_remote", "reliable")$/d' "$M"
net_case "game code: @rpc removed from sync_hp (expect FAIL)" --port $((NP + 14))
cp "$WORK/net_match.orig" "$M"
timeout 60 "$GODOT_BIN" --headless --path "$NETC" --script res://_hold_udp_port.gd -- --port=$((NP + 15)) --seconds=40 \
  > "$WORK/logs/net_hold.log" 2>&1 & hold=$!
sleep 1
net_case "port already taken by a plain UDP socket (expect FAIL, bounded by the harness WAIT, not ENet's 31 s)" \
  --port $((NP + 15))
kill $hold 2>/dev/null; wait $hold 2>/dev/null
tr -d '\r' < "$WORK/logs/net_hold.log" | grep '^\[hold\]' | sed 's/^/    | /'
echo "    (the count above includes the port holder; after stopping it: engine processes left=$(engines_left))"
cmp -s "$H" "$WORK/netdiag_hits.orig" && cmp -s "$M" "$WORK/net_match.orig" && echo "    (harness and net_match restored)"

# Kit: the multiplayer scaffold - a fresh harness FAILS on both sides; with the placeholders gone the template's own
# skeleton (listen, connect, done handshake) PASSES, with one client and with three.
NS="$ROOT/skills/godot-multiplayer-harness/scaffold.sh"
bash "$NS" --path "$NETC" probe > /dev/null
nscaffold() {  # nscaffold <label> [net_run.sh args...]
  local label="$1"; shift
  GODOT_BIN="$GODOT_BIN" bash "$NET" --path "$NETC" "$@" res://tools/netdiag_probe.tscn > "$WORK/logs/net_scaffold.out" 2>&1
  printf '\n=== KIT net scaffold: %s\n    exit=%s\n' "$label" $?
  grep -E '^== |GODOT-NET|^ +\| +[0-9]+: *(ok|FAIL)' "$WORK/logs/net_scaffold.out" | sed 's/^ */    | /'
}
nscaffold "fresh harness (expect FAIL on both sides: placeholders)" --port $((NP + 20))
sed -i '/placeholder replaced by real/d; s/^const EXPECTED := {"server": 4, "client": 2}$/const EXPECTED := {"server": 3, "client": 1}/' \
  "$NETC/tools/netdiag_probe.gd"
nscaffold "placeholders removed, template skeleton only (expect PASS)" --no-import --port $((NP + 21))
nscaffold "the same with --clients 3 (expect PASS, server + 3 clients)" --no-import --clients 3 --port $((NP + 22))

# Kit: the static RPC check - clean demo, the sync_hp sabotage, and the edge-case fixture (exactly 3 BAD lines).
RC="$ROOT/skills/godot-multiplayer-harness/rpc_check.sh"
rc_case() {  # rc_case <label> <project>
  bash "$RC" --path "$2" > "$WORK/logs/rpc_check.out" 2>&1
  printf '\n=== KIT rpc_check.sh: %s\n    exit=%s\n' "$1" $?
  sed 's/^ */    | /' "$WORK/logs/rpc_check.out"
}
# The probes misuse RPCs on purpose (N2) - they would be (rightly) reported here.
rm -rf "$NETC/tools/netdiag_probe.gd" "$NETC/tools/netdiag_probe.tscn" "$NETC/_net_probe.gd" "$NETC/_hold_udp_port.gd"
rc_case "demo (expect PASS)" "$NETC"
sed -i '/^@rpc("authority", "call_remote", "reliable")$/d' "$M"
rc_case "@rpc removed from sync_hp (expect FAIL naming net_match.gd sync_hp)" "$NETC"
cp "$WORK/net_match.orig" "$M"
cp "$FIX/rpc_cases.gd" "$NETC/src/_rpc_cases.gd"; mkdir -p "$NETC/addons/thirdparty"; cp "$FIX/rpc_addon.gd" "$NETC/addons/thirdparty/rpc_addon.gd"
rc_case "edge cases: same-line @rpc, annotation stack, object form, StringName, rpc_config, addon declaration + addon bad call, comment, string, variable (expect exactly the 3 BAD lines)" "$NETC"
rm -rf "$NETC/src/_rpc_cases.gd" "$NETC/addons/thirdparty"

# Kit: runner --import-only on a fresh copy, then a --no-import run must find the cache.
IO="$WORK/importonly"; rm -rf "$IO"; cp -r "$DEMO" "$IO"; rm -rf "$IO/.godot"
GODOT_BIN="$GODOT_BIN" bash "$ROOT/skills/godot-run/godot_run.sh" --path "$IO" --import-only > "$WORK/logs/importonly.out" 2>&1
printf '\n=== KIT godot_run.sh --import-only on a fresh copy (expect IMPORTED, .godot/ created)\n    exit=%s, .godot exists=%s\n' \
  $? "$([ -d "$IO/.godot" ] && echo yes || echo no)"
grep 'GODOT-RUN' "$WORK/logs/importonly.out" | sed 's/^/    | /'
GODOT_BIN="$GODOT_BIN" bash "$ROOT/skills/godot-run/godot_run.sh" --path "$IO" --no-import --banner '^DIAG-HEALTH: PASS' \
  res://tools/diag_health.tscn 2>&1 | tail -1 | sed 's/^/    | then --no-import diag_health: /'

# ---------------------------------------------------------------------------------------------------------------------
# Unit-test frameworks: GUT 9.7.1 and gdUnit4 6.2.2, pinned by sha256. This script downloads nothing: put the two
# release zips into the cache dir yourself (GCK_FW_CACHE, default gck_fw_cache in the temp dir; the missing ones and
# their URLs are printed). A missing zip or a checksum mismatch makes this section say SKIPPED - it never passes
# silently. U1-U10 run the frameworks' own CLIs; the KIT cases run test_run.sh.
FWC="${GCK_FW_CACHE:-${TMPDIR:-${TEMP:-/tmp}}/gck_fw_cache}"; mkdir -p "$FWC"
fw_fetch() {  # fw_fetch <name> <url> <sha256> <addon dir in the archive> -> prints the addon path, or nothing
  local z="$FWC/$1.zip" x="$FWC/$1"
  [ -f "$z" ] || { echo "    missing $z - download $2 to that path" >&2; return 1; }
  # sha256sum reads stdin: given a path with backslashes (TEMP on Windows) it escapes the name and prefixes the line
  # with "\", which broke the comparison once.
  [ "$(sha256sum < "$z" | cut -d' ' -f1)" = "$3" ] || { echo "    checksum mismatch: $z" >&2; return 1; }
  if [ ! -d "$x/$4" ]; then
    mkdir -p "$x"
    if command -v unzip > /dev/null; then unzip -q -o "$z" -d "$x"; else python3 -m zipfile -e "$z" "$x"; fi
  fi
  [ -d "$x/$4" ] && echo "$x/$4"
}
GUT_ADDON=$(fw_fetch gut-9.7.1 https://github.com/bitwes/Gut/archive/refs/tags/v9.7.1.zip \
  14969aa46adc84aa08cdd21b9f6d1a64addd92ae60b36f02d0521ed305aa4086 Gut-9.7.1/addons/gut)
GDU_ADDON=$(fw_fetch gdunit4-6.2.2 https://github.com/godot-gdunit-labs/gdUnit4/archive/refs/tags/v6.2.2.zip \
  ddb44730ffb9cd77fd70d283753450759b00c5016143d7572bf63625f64d5433 gdUnit4-6.2.2/addons/gdUnit4)
TR="$ROOT/skills/godot-unit-tests/test_run.sh"
ucopy() {  # ucopy <name> <gut|gdunit> [noimport]: demo copy + framework + its fixture test, imported unless noimport
  local u="$WORK/$1"; cp -r "$DEMO" "$u"; rm -rf "$u/.godot"; mkdir -p "$u/addons" "$u/tests/$2"
  if [ "$2" = gut ]; then cp -r "$GUT_ADDON" "$u/addons/gut"; cp "$ROOT/tests/fixtures/gut/test_health.gd" "$u/tests/gut/"
  else cp -r "$GDU_ADDON" "$u/addons/gdUnit4"; cp "$ROOT/tests/fixtures/gdunit/test_health_suite.gd" "$u/tests/gdunit/"; fi
  [ "${3:-}" = noimport ] || godot --headless --path "$u" --import > "$WORK/logs/$1_import.log" 2>&1
}
ushow() {  # ushow <label> <exit> <log>: the framework's own summary lines
  printf '\n=== %s\n    exit=%s\n' "$1" "$2"
  tr -d '\r' < "$3" | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Parse Error|^ERROR: |Ignoring script|GUT ERROR|passed\.|All tests|failing tests|class_names|No test cases|Exit code|Overall Summary|Headless mode is not|debug>|Abnormal' \
    | grep -vE 'Unreferenced static|RID allocations|PagedAllocator|leaked at exit' | sort -u | head -8 | sed 's/^/    | /'
}
gut_cli() {  # gut_cli <copy> <log> [args]
  local u="$WORK/$1" l="$WORK/logs/$2"; shift 2
  timeout 120 "$GODOT_BIN" --headless --path "$u" -s res://addons/gut/gut_cmdln.gd -gexit -gdisable_colors "$@" > "$l" 2>&1
}
gdu_cli() {  # gdu_cli <copy> <log> [args] - never -d (see U9)
  local u="$WORK/$1" l="$WORK/logs/$2"; shift 2
  timeout "${UTO:-120}" "$GODOT_BIN" --headless --path "$u" -s ${GDU_D:-} res://addons/gdUnit4/bin/GdUnitCmdTool.gd -c "$@" > "$l" 2>&1
}
if [ -z "$GUT_ADDON" ] || [ -z "$GDU_ADDON" ]; then
  printf '\n=== U1-U10 + KIT test_run.sh: SKIPPED (GUT/gdUnit4 zip missing from %s, or checksum mismatch)\n' "$FWC"
else
  ucopy ug gut
  gut_cli ug u1.log -gdir=res://tests/gut; ushow "U1 GUT clean demo tests (expect exit 0, 2/2)" $? "$WORK/logs/u1.log"
  cp -r "$WORK/ug" "$WORK/ug2"; cp "$FIX/syntax_error.gd" "$WORK/ug2/tests/gut/test_broken.gd"
  gut_cli ug2 u2.log -gdir=res://tests/gut; ushow "U2 GUT with a test file that does not parse" $? "$WORK/logs/u2.log"
  cp -r "$WORK/ug" "$WORK/ug3"; printf 'extends Node\n\n\nfunc test_not_a_guttest() -> void:\n\tpass\n' > "$WORK/ug3/tests/gut/test_wrong_base.gd"
  gut_cli ug3 u3.log -gdir=res://tests/gut; ushow "U3 GUT with a test file that does not extend GutTest" $? "$WORK/logs/u3.log"
  gut_cli ug u4.log -gdir=res://tests/nothing_here; ushow "U4 GUT with a test directory that does not exist" $? "$WORK/logs/u4.log"
  mkdir -p "$WORK/ug/tests/empty"
  gut_cli ug u4b.log -gdir=res://tests/empty; ushow "U4b GUT with an empty test directory" $? "$WORK/logs/u4b.log"
  cp -r "$WORK/ug" "$WORK/ug4c"; mv "$WORK/ug4c/tests/gut/test_health.gd" "$WORK/ug4c/tests/gut/health_test.gd"
  gut_cli ug4c u4c.log -gdir=res://tests/gut; ushow "U4c GUT, test file without the test_ prefix" $? "$WORK/logs/u4c.log"
  ucopy ug5 gut noimport
  gut_cli ug5 u5.log -gdir=res://tests/gut; ushow "U5 GUT on a fresh clone without --import" $? "$WORK/logs/u5.log"
  cp -r "$WORK/ug" "$WORK/ug6"
  printf 'extends GutTest\n\n\nfunc test_expects_push_error() -> void:\n\tpush_error("expected failure path")\n\tassert_push_error("expected failure path")\n' \
    > "$WORK/ug6/tests/gut/test_expect_error.gd"
  gut_cli ug6 u6.log -gdir=res://tests/gut; ushow "U6 GUT, a PASSING test that expects push_error (expect an ERROR: line anyway)" $? "$WORK/logs/u6.log"
  ucopy ud gdunit
  gdu_cli ud u7.log -a res://tests/gdunit; ushow "U7 gdUnit4 headless WITHOUT --ignoreHeadlessMode" $? "$WORK/logs/u7.log"
  gdu_cli ud u8.log -a res://tests/nothing_here --ignoreHeadlessMode; ushow "U8 gdUnit4 with a test directory that does not exist" $? "$WORK/logs/u8.log"
  mkdir -p "$WORK/ud/tests/empty"
  gdu_cli ud u8b.log -a res://tests/empty --ignoreHeadlessMode; ushow "U8b gdUnit4 with an empty test directory" $? "$WORK/logs/u8b.log"
  cp -r "$WORK/ud" "$WORK/ud9"; cp "$FIX/syntax_error.gd" "$WORK/ud9/tests/gdunit/test_broken_suite.gd"
  UTO=20 GDU_D=-d gdu_cli ud9 u9.log -a res://tests/gdunit --ignoreHeadlessMode
  ushow "U9 gdUnit4 with -d and a test file that does not parse (timeout 20 s)" $? "$WORK/logs/u9.log"
  gdu_cli ud9 u9b.log -a res://tests/gdunit --ignoreHeadlessMode; ushow "U9b the same without -d" $? "$WORK/logs/u9b.log"
  cp -r "$WORK/ud" "$WORK/ud10"; rm -rf "$WORK/ud10/reports"
  gdu_cli ud10 u10.log -a res://tests/gdunit --ignoreHeadlessMode
  printf '\n=== U10 gdUnit4 default run: files it wrote into the project\n    exit=%s, reports/ files=%s\n' $? \
    "$(find "$WORK/ud10/reports" -type f 2>/dev/null | wc -l | tr -d ' ')"

  tcase() {  # tcase <label> <copy> [test_run.sh args]
    local label="$1" u="$WORK/$2"; shift 2
    GODOT_BIN="$GODOT_BIN" bash "$TR" --path "$u" "$@" > "$WORK/logs/test_run.out" 2>&1
    printf '\n=== KIT test_run.sh: %s\n    exit=%s\n' "$label" $?
    tail -1 "$WORK/logs/test_run.out" | sed 's/^/    | /'
  }
  tcase "GUT clean (expect PASS 2)" ug --no-import --dir res://tests/gut
  tcase "GUT, test file does not parse (expect FAIL)" ug2 --no-import --dir res://tests/gut
  tcase "GUT, test file does not extend GutTest (expect FAIL)" ug3 --no-import --dir res://tests/gut
  tcase "GUT, missing test directory (expect FAIL)" ug --no-import --dir res://tests/nothing_here
  cp -r "$WORK/ug" "$WORK/ug7"; cp "$FIX/health_no_clamp.gd" "$WORK/ug7/src/health.gd"
  tcase "GUT, Health clamp removed (expect FAIL, 1 failing)" ug7 --no-import --dir res://tests/gut
  tcase "GUT, passing test expecting push_error (expect PASS 3)" ug6 --no-import --dir res://tests/gut
  tcase "GUT, fresh clone - test_run.sh imports (expect PASS 2)" ug5 --dir res://tests/gut
  tcase "GUT, --min-tests 3 with 2 tests (expect FAIL)" ug --no-import --dir res://tests/gut --min-tests 3
  tcase "gdUnit4 clean (expect PASS 2)" ud --no-import --dir res://tests/gdunit
  cp -r "$WORK/ud" "$WORK/ud11"; cp "$FIX/health_no_clamp.gd" "$WORK/ud11/src/health.gd"
  tcase "gdUnit4, Health clamp removed (expect FAIL, 1 failing)" ud11 --no-import --dir res://tests/gdunit
  tcase "gdUnit4, test file does not parse (expect FAIL)" ud9 --no-import --dir res://tests/gdunit
  mkdir -p "$WORK/ud/tests/empty"
  tcase "gdUnit4, empty test directory (expect FAIL)" ud --no-import --dir res://tests/empty
  cp -r "$WORK/ud" "$WORK/ud12"; rm -rf "$WORK/ud12/reports"
  printf 'extends GdUnitTestSuite\n\n\nfunc test_leaks_a_node() -> void:\n\tvar n := Node.new()\n\tassert_bool(n != null).is_true()\n' \
    > "$WORK/ud12/tests/gdunit/test_orphan_suite.gd"
  ( cd "$WORK/ud12" && find . -path ./.godot -prune -o -type f -print | sort ) > "$WORK/ud12.files_before"
  tcase "gdUnit4, orphan node = exit 101 (expect PASS with a warnings note)" ud12 --no-import --dir res://tests/gdunit
  tcase "the same with --strict (expect FAIL)" ud12 --no-import --dir res://tests/gdunit --strict
  # A full file diff, not a reports/ count: on Linux gdUnit4 once wrote into <project>/tmp/... (it maps "/..." to res://).
  ( cd "$WORK/ud12" && find . -path ./.godot -prune -o -type f -print | sort ) > "$WORK/ud12.files_after"
  printf '    (project files added or removed by these two test_run.sh runs: %s - expect 0)\n' \
    "$(diff "$WORK/ud12.files_before" "$WORK/ud12.files_after" | grep -c '^[<>]')"
fi

# ---------------------------------------------------------------------------------------------------------------------
# Screenshots. S1-S9 run tests/sabotage/shot_probe.gd as a --script on a demo copy (a naive capture: it reports what it
# got, it judges nothing); the KIT cases run shot.sh and ci.sh --shot-dir. Anything that must draw needs a display:
# Windows always has one (the window is parked off-screen), Linux only via xvfb-run - without it those cases say
# SKIPPED, never PASS.
SP="$WORK/shot"; rm -rf "$SP"; cp -r "$DEMO" "$SP"; rm -rf "$SP/.godot"; mkdir -p "$WORK/shots"
godot --headless --path "$SP" --import > "$WORK/logs/s_import.log" 2>&1
nat() { if command -v cygpath > /dev/null; then cygpath -m "$1"; else echo "$1"; fi; }
PROBE=$(nat "$FIX/shot_probe.gd")
sshow() {  # sshow <label> <exit> <log>
  printf '\n=== %s\n    exit=%s\n' "$1" "$2"
  grep -E '^probe: (image|done)|SCRIPT ERROR|^ERROR|crashed|Unable to create DisplayServer|Movie Maker' "$3" | tr -d '\r' \
    | sed 's/^/    | /' | head -6
  grep -q '^probe: done' "$3" || echo "    | (no 'probe: done' line)"
}
WIN_DISPLAY=0 XV=()
case "$(uname -s)" in
  Linux) if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v xvfb-run > /dev/null; then
           XV=(xvfb-run -a -s "-screen 0 1280x720x24"); fi ;;
  *) WIN_DISPLAY=1 ;;
esac
POS=(); [ "$WIN_DISPLAY" = 1 ] && POS=(--position -10000,-10000)
GL=(); [ ${#XV[@]} -gt 0 ] && GL=(--rendering-driver opengl3)   # Vulkan on llvmpipe crashes, see S7
can_draw() { [ "$WIN_DISPLAY" = 1 ] || [ ${#XV[@]} -gt 0 ]; }
# --audio-driver Dummy: with ALSA but no sound card every drawing run logs an audio ERROR (S10) - noise here.
win() { ${XV[@]+"${XV[@]}"} "$GODOT_BIN" --path "$SP" ${POS[@]+"${POS[@]}"} --audio-driver Dummy "$@"; }   # a run that draws

s=$(date +%s%N)
godot --headless --path "$SP" --quit-after 600 --script "$PROBE" ++ --scene=res://src/main.tscn > "$WORK/logs/s1.log" 2>&1
e=$?; sshow "S1 --headless capture that awaits frame_post_draw (--quit-after 600)" $e "$WORK/logs/s1.log"
echo "    wall=$(( ($(date +%s%N) - s) / 1000000 ))ms"
godot --headless --path "$SP" --quit-after 600 --script "$PROBE" ++ --no-post-draw > "$WORK/logs/s2.log" 2>&1
sshow "S2 --headless capture without the await" $? "$WORK/logs/s2.log"
godot --headless --path "$SP" --write-movie "$(nat "$WORK/shots/s3.png")" --fixed-fps 10 --quit-after 5 res://src/main.tscn \
  > "$WORK/logs/s3.log" 2>&1
sshow "S3 --headless --write-movie" $? "$WORK/logs/s3.log"
if [ "$(uname -s)" = Linux ]; then
  env -u DISPLAY -u WAYLAND_DISPLAY "$GODOT_BIN" --path "$SP" --quit-after 600 --script "$PROBE" > "$WORK/logs/s8.log" 2>&1
  sshow "S8 (Linux) no display, no --headless" $? "$WORK/logs/s8.log"
fi
if can_draw; then
  for f in 0 1; do   # grabbed before anything is drawn: at startup (frame 0) and with the scene in (frame 1)
    win ${GL[@]+"${GL[@]}"} --quit-after 600 --script "$PROBE" ++ --frames=$f --no-post-draw > "$WORK/logs/s4_$f.log" 2>&1
    sshow "S4 drawing run, image grabbed after $f frame(s) without waiting for the draw" $? "$WORK/logs/s4_$f.log"
  done
  win ${GL[@]+"${GL[@]}"} --quit-after 600 --script "$PROBE" ++ --scene=res://src/enemy.tscn > "$WORK/logs/s5.log" 2>&1
  sshow "S5 drawing run, a 3D scene without a camera (enemy.tscn)" $? "$WORK/logs/s5.log"
  for i in 1 2; do
    win ${GL[@]+"${GL[@]}"} --quit-after 600 --script "$PROBE" ++ --out="$(nat "$WORK/shots/s6_$i.png")" > "$WORK/logs/s6_$i.log" 2>&1
  done
  printf '\n=== S6 main.tscn twice, same driver\n    %s\n' \
    "$(cmp -s "$WORK/shots/s6_1.png" "$WORK/shots/s6_2.png" && echo "PNGs BYTE-IDENTICAL" || echo "PNGs differ")"
  if [ "$WIN_DISPLAY" = 1 ]; then
    win --rendering-driver opengl3 --quit-after 600 --script "$PROBE" ++ --out="$(nat "$WORK/shots/s6_gl.png")" > "$WORK/logs/s6_gl.log" 2>&1
    printf '    default driver vs opengl3: %s\n' \
      "$(cmp -s "$WORK/shots/s6_1.png" "$WORK/shots/s6_gl.png" && echo "BYTE-IDENTICAL" || echo "PNGs differ")"
  fi
  if [ ${#XV[@]} -gt 0 ]; then
    win --quit-after 600 --script "$PROBE" > "$WORK/logs/s7.log" 2>&1
    sshow "S7 (Linux, xvfb) default Vulkan on llvmpipe" $? "$WORK/logs/s7.log"
  fi
  cp "$SP/src/main.gd" "$WORK/main.gd.orig"; cp "$FIX/syntax_error.gd" "$SP/src/main.gd"
  win ${GL[@]+"${GL[@]}"} --quit-after 600 --script "$PROBE" ++ --out="$(nat "$WORK/shots/s9.png")" > "$WORK/logs/s9.log" 2>&1
  sshow "S9 drawing run, main.gd does not parse" $? "$WORK/logs/s9.log"
  cp "$WORK/main.gd.orig" "$SP/src/main.gd"
  # S10 - the audio driver of a drawing run (headless uses a dummy one). On a machine with ALSA but no sound card
  # (a CI runner; here: Debian with libasound2t64 and no card) the default driver logs an ERROR on every run.
  for ad in default Dummy; do
    adarg=(); [ "$ad" = Dummy ] && adarg=(--audio-driver Dummy)
    ${XV[@]+"${XV[@]}"} "$GODOT_BIN" --path "$SP" ${POS[@]+"${POS[@]}"} ${GL[@]+"${GL[@]}"} ${adarg[@]+"${adarg[@]}"} \
      --quit-after 60 res://src/main.tscn > "$WORK/logs/s10_$ad.log" 2>&1
    rc=$?
    printf '\n=== S10 drawing run of main.tscn, audio driver %s\n    exit=%s, ERROR lines: %s\n' "$ad" $rc \
      "$(grep -c '^ERROR' "$WORK/logs/s10_$ad.log")"
    grep -A1 '^ERROR' "$WORK/logs/s10_$ad.log" | tr -d '\r' | sed 's/^/    | /' | head -2
  done
else
  printf '\n=== S4-S7, S9: SKIPPED (no display and no xvfb-run)\n'
fi

SHOT="$ROOT/skills/godot-screenshot/shot.sh"; CIS="$WORK/logs/ci_shot.out"
shcase() {  # shcase <label> [shot.sh args]
  local label="$1"; shift
  GODOT_BIN="$GODOT_BIN" bash "$SHOT" --path "$SP" --no-import "$@" > "$WORK/logs/shot.out" 2>&1
  printf '\n=== KIT shot.sh: %s\n    exit=%s\n' "$label" $?
  grep -E '^  golden: rmse|^GODOT-SHOT' "$WORK/logs/shot.out" | sed "s|$(nat "$WORK")|<work>|g; s/^ */    | /"
}
if can_draw; then
  shcase "main.tscn (expect PASS)" --out "$WORK/shots/k_default.png"
  shcase "enemy.tscn, no camera (expect FAIL: blank frame)" --scene res://src/enemy.tscn --out "$WORK/shots/k_enemy.png"
  shcase "write a golden (expect PASS, .gdignore written)" --out "$WORK/shots/k_g.png" --golden "$SP/tests/kit_shots/kit.png" --update-golden
  printf '    (.gdignore next to the golden: %s)\n' "$([ -e "$SP/tests/kit_shots/.gdignore" ] && echo yes || echo NO)"
  shcase "same scene vs that golden (expect PASS, rmse 0.000)" --out "$WORK/shots/k_same.png" --golden "$SP/tests/kit_shots/kit.png"
  cp "$SP/tests/kit_shots/kit.png" "$WORK/golden.before.png"
  shcase "--out and --golden the same file (expect FAIL, golden untouched)" --out "$SP/tests/kit_shots/kit.png" --golden "$SP/tests/kit_shots/kit.png"
  printf '    (golden unchanged: %s)\n' "$(cmp -s "$WORK/golden.before.png" "$SP/tests/kit_shots/kit.png" && echo yes || echo NO)"
  shcase "same golden at another --size (expect FAIL)" --out "$WORK/shots/k_size.png" --golden "$SP/tests/kit_shots/kit.png" --size 640x360
  if [ "$WIN_DISPLAY" = 1 ]; then
    shcase "golden from the default driver, run with opengl3 (expect UNVERIFIED)" --out "$WORK/shots/k_gl.png" \
      --golden "$SP/tests/kit_shots/kit.png" --driver opengl3
  fi
  cp "$SP/src/main.tscn" "$WORK/main.tscn.orig"
  sed -i 's/text = "score: 0"/text = "score: 8"/' "$SP/src/main.tscn"
  shcase "HUD text score: 0 -> 8 (expect FAIL, rmse ~1.4)" --out "$WORK/shots/k_8.png" --golden "$SP/tests/kit_shots/kit.png"
  cp "$WORK/main.tscn.orig" "$SP/src/main.tscn"
  sed -i 's/offset_left = 16.0/offset_left = 5000.0/' "$SP/src/main.tscn"
  shcase "HUD label moved off-screen (expect FAIL, rmse ~4.4)" --out "$WORK/shots/k_off.png" --golden "$SP/tests/kit_shots/kit.png"
  GODOT_BIN="$GODOT_BIN" bash "$CI" --path "$SP" --shot-dir res://tests/kit_shots > "$CIS" 2>&1
  printf '\n=== KIT ci.sh --shot-dir, label still off-screen (expect FAIL: shot:main)\n    exit=%s\n' $?
  grep -E '^   (PASS|FAIL|SKIP)  shot|^GODOT-CI' "$CIS" | sed 's/^ */    | /'
  cp "$WORK/main.tscn.orig" "$SP/src/main.tscn"
  GODOT_BIN="$GODOT_BIN" bash "$CI" --path "$SP" --shot-dir res://tests/kit_shots > "$CIS" 2>&1
  printf '\n=== KIT ci.sh --shot-dir, restored (expect PASS, 1 shot)\n    exit=%s\n' $?
  grep -E '^   (PASS|FAIL|SKIP)  shot|^GODOT-CI' "$CIS" | sed 's/^ */    | /'
  # A golden whose fingerprint no longer matches (as after a CI image update bumped Mesa): a note, or with
  # --require-shots a FAIL.
  mkdir -p "$SP/tests/shots_other"; : > "$SP/tests/shots_other/.gdignore"
  cp "$SP/tests/kit_shots/kit.png" "$SP/tests/shots_other/kit.png"
  sed 's/"api": "[^"]*"/"api": "0.0 (another driver)"/' "$SP/tests/kit_shots/kit.json" > "$SP/tests/shots_other/kit.json"
  for req in "" --require-shots; do
    GODOT_BIN="$GODOT_BIN" bash "$CI" --path "$SP" --shot-dir res://tests/shots_other $req > "$CIS" 2>&1
    rc=$?   # before the $(...) below, which would overwrite it
    printf '\n=== KIT ci.sh --shot-dir %s, golden from another renderer (expect %s)\n    exit=%s\n' "$req" \
      "$([ -n "$req" ] && echo FAIL || echo 'PASS, not compared')" $rc
    grep -E '^   (PASS|FAIL|SKIP)  shot|^GODOT-CI' "$CIS" | sed 's/^ */    | /'
  done
  rm -rf "$WORK/cand"
  GODOT_BIN="$GODOT_BIN" bash "$CI" --path "$SP" --shot-dir res://tests/shots_other --require-shots --candidates "$WORK/cand" \
    > "$CIS" 2>&1
  printf '\n=== KIT ci.sh --candidates, golden from another renderer (expect FAIL + candidate png/json for this renderer)\n    exit=%s\n' $?
  grep -E '^   (PASS|FAIL)  shot|^GODOT-CI' "$CIS" | sed 's/^ */    | /'
  printf '    (candidate: png %s, json %s, driver %s; shots_other untouched: %s)\n' \
    "$([ -s "$WORK/cand/kit.png" ] && echo yes || echo NO)" "$([ -s "$WORK/cand/kit.json" ] && echo yes || echo NO)" \
    "$(sed -n 's/.*"driver": "\(.*\)".*/\1/p' "$WORK/cand/kit.json" 2>/dev/null)" \
    "$(grep -q 'another driver' "$SP/tests/shots_other/kit.json" && echo yes || echo NO)"
else
  printf '\n=== KIT shot.sh drawing cases: SKIPPED (no display and no xvfb-run)\n'
fi
if [ "$(uname -s)" = Linux ]; then
  # No display and no xvfb-run: a PATH with every system tool except xvfb-run and Xvfb.
  NOX="$WORK/nopath"; rm -rf "$NOX"; mkdir -p "$NOX"
  for p in /usr/bin/* /bin/*; do
    case "${p##*/}" in xvfb-run|Xvfb) ;; *) [ -e "$NOX/${p##*/}" ] || ln -s "$p" "$NOX/${p##*/}" ;; esac
  done
  mkdir -p "$SP/tests/kit_shots"
  env -u DISPLAY -u WAYLAND_DISPLAY PATH="$NOX" GODOT_BIN="$GODOT_BIN" bash "$SHOT" --path "$SP" --no-import \
    --out "$WORK/shots/k_nd.png" > "$WORK/logs/shot.out" 2>&1
  printf '\n=== KIT shot.sh (Linux) without display and xvfb-run (expect NO-DISPLAY, exit 4)\n    exit=%s\n' $?
  tail -1 "$WORK/logs/shot.out" | sed 's/^/    | /'
  if [ -f "$SP/tests/kit_shots/kit.json" ]; then
    env -u DISPLAY -u WAYLAND_DISPLAY PATH="$NOX" GODOT_BIN="$GODOT_BIN" bash "$CI" --path "$SP" --shot-dir res://tests/kit_shots \
      > "$CIS" 2>&1
    printf '\n=== KIT ci.sh --shot-dir (Linux) without display and xvfb-run (expect PASS with shots SKIPPED)\n    exit=%s\n' $?
    grep -E '^   (PASS|FAIL|SKIP)  shot|^GODOT-CI' "$CIS" | sed 's/^ */    | /'
    env -u DISPLAY -u WAYLAND_DISPLAY PATH="$NOX" GODOT_BIN="$GODOT_BIN" bash "$CI" --path "$SP" --shot-dir res://tests/kit_shots \
      --require-shots > "$CIS" 2>&1
    printf '\n=== KIT ci.sh --shot-dir --require-shots (Linux) without display and xvfb-run (expect FAIL)\n    exit=%s\n' $?
    grep -E '^   (PASS|FAIL|SKIP)  shot|^GODOT-CI' "$CIS" | sed 's/^ */    | /'
  fi
fi

# ---------------------------------------------------------------------------------------------------------------------
# GDScript warnings and review traps. W1-W5 run the engine on a demo copy with one fixture at a time; the KIT cases
# run warnings.sh (skill godot-headless-harness).
WP="$WORK/warn"; rm -rf "$WP"; cp -r "$DEMO" "$WP"; rm -rf "$WP/.godot"
wimport() { "$GODOT_BIN" --headless --path "$WP" --import > "$WORK/logs/w_import.log" 2>&1; }
wcount() { tr -d '\r' < "$1" | grep -c '^WARNING: .*' ; }
wshow() {  # wshow <label> <exit> <log>: exit, WARNING count, the warnings with their file:line
  printf '\n=== %s\n    exit=%s, WARNING lines: %s\n' "$1" "$2" "$(tr -d '\r' < "$3" | grep -c '^WARNING')"
  tr -d '\r' < "$3" | awk '/^WARNING: /{m=substr($0,10);next} m!="" && /at: GDScript::reload/{l=$0;sub(/.*\(/,"",l);sub(/\).*/,"",l);print "    | " l ": " m} {m=""}' | head -8
  tr -d '\r' < "$3" | grep -E '^(PARSE-GATE|Debugger Break)|^ERROR: Node not found|^TRAP:' | sed 's/^/    | /' | head -3
}
cp "$FIX/warn_cases.gd" "$WP/src/_warn.gd"; wimport
timeout 60 "$GODOT_BIN" --headless --path "$WP" --check-only --script res://src/_warn.gd < /dev/null > "$WORK/logs/w1a.log" 2>&1
wshow "W1 --check-only on a script with six warnings" $? "$WORK/logs/w1a.log"
timeout 60 "$GODOT_BIN" --headless --path "$WP" res://tools/ci/parse_gate.tscn < /dev/null > "$WORK/logs/w1b.log" 2>&1
wshow "W1 parse gate with that script" $? "$WORK/logs/w1b.log"
timeout 60 "$GODOT_BIN" --headless --debug --path "$WP" res://tools/ci/parse_gate.tscn < /dev/null > "$WORK/logs/w1c.log" 2>&1
wshow "W1 the same gate with --debug" $? "$WORK/logs/w1c.log"
cp "$FIX/syntax_error.gd" "$WP/src/_bad.gd"; wimport
# In a subshell that waits (the `exit` keeps bash from exec-ing the command): on Linux this crashes, and bash's own
# crash message must land in the log, not over this script's output.
( timeout 30 "$GODOT_BIN" --headless --debug --path "$WP" --check-only --script res://src/_bad.gd < /dev/null; exit $? ) \
  > "$WORK/logs/w2a.log" 2>&1
wshow "W2 --debug --check-only on a syntax error, stdin closed (timeout 30 s)" $? "$WORK/logs/w2a.log"
timeout 30 "$GODOT_BIN" --headless --debug --path "$WP" res://tools/ci/parse_gate.tscn < /dev/null > "$WORK/logs/w2b.log" 2>&1
wshow "W2 --debug parse gate with that syntax error, stdin closed (timeout 30 s)" $? "$WORK/logs/w2b.log"
rm -f "$WP/src/_bad.gd" "$WP/src/_bad.gd.uid" "$WP/src/_warn.gd" "$WP/src/_warn.gd.uid"
cp "$FIX/coro_unawaited.gd" "$WP/src/_coro.gd"; wimport
timeout 60 "$GODOT_BIN" --headless --debug --path "$WP" res://tools/ci/parse_gate.tscn < /dev/null > "$WORK/logs/w3a.log" 2>&1
wshow "W3 --debug gate, two coroutine calls without await, default settings" $? "$WORK/logs/w3a.log"
cp "$WP/project.godot" "$WORK/w_project.orig"
printf '\n[debug]\n\ngdscript/warnings/missing_await=1\n' >> "$WP/project.godot"
timeout 60 "$GODOT_BIN" --headless --debug --path "$WP" res://tools/ci/parse_gate.tscn < /dev/null > "$WORK/logs/w3b.log" 2>&1
wshow "W3 the same with debug/gdscript/warnings/missing_await=1" $? "$WORK/logs/w3b.log"
cp "$WORK/w_project.orig" "$WP/project.godot"; rm -f "$WP/src/_coro.gd" "$WP/src/_coro.gd.uid"
cp "$FIX/warn_cases.gd" "$WP/src/_warn.gd"
printf '\n[debug]\n\ngdscript/warnings/unused_variable=2\n' >> "$WP/project.godot"; wimport
timeout 60 "$GODOT_BIN" --headless --path "$WP" res://tools/ci/parse_gate.tscn < /dev/null > "$WORK/logs/w4.log" 2>&1
printf '\n=== W4 normal gate, unused_variable set to error, script with an unused variable\n    exit=%s\n' $?
tr -d '\r' < "$WORK/logs/w4.log" | grep -E '^PARSE-GATE|FAIL  ' | sed 's/^/    | /'
cp "$WORK/w_project.orig" "$WP/project.godot"; rm -f "$WP/src/_warn.gd" "$WP/src/_warn.gd.uid"
cp "$FIX/node_path_missing.gd" "$WP/tools/_trap.gd"
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://tools/_trap.gd" id="1"]\n\n[node name="Trap" type="Node"]\nscript = ExtResource("1")\n' > "$WP/tools/_trap.tscn"
wimport
timeout 60 "$GODOT_BIN" --headless --path "$WP" res://tools/ci/parse_gate.tscn < /dev/null > "$WORK/logs/w5a.log" 2>&1
wshow "W5 parse gate, a script whose \$Hud the scene does not have" $? "$WORK/logs/w5a.log"
timeout 60 "$GODOT_BIN" --headless --path "$WP" --quit-after 600 res://tools/_trap.tscn < /dev/null > "$WORK/logs/w5b.log" 2>&1
wshow "W5 running that scene" $? "$WORK/logs/w5b.log"
rm -f "$WP/tools/_trap.gd" "$WP/tools/_trap.gd.uid" "$WP/tools/_trap.tscn"
cp "$FIX/warn_cases.gd" "$WP/src/_warn.gd"
printf '\n[debug]\n\ngdscript/warnings/enable=false\n' >> "$WP/project.godot"; wimport
timeout 60 "$GODOT_BIN" --headless --debug --path "$WP" res://tools/ci/parse_gate.tscn < /dev/null > "$WORK/logs/w6.log" 2>&1
wshow "W6 --debug gate, six-warning script, debug/gdscript/warnings/enable=false" $? "$WORK/logs/w6.log"
cp "$WORK/w_project.orig" "$WP/project.godot"; rm -f "$WP/src/_warn.gd" "$WP/src/_warn.gd.uid"; wimport

WARN="$ROOT/skills/godot-headless-harness/warnings.sh"
wcase() {  # wcase <label> [warnings.sh args]
  local label="$1"; shift
  GODOT_BIN="$GODOT_BIN" bash "$WARN" --path "$WP" "$@" > "$WORK/logs/warn.out" 2>&1
  printf '\n=== KIT warnings.sh: %s\n    exit=%s\n' "$label" $?
  grep -E '^  res://|^  note:|^GODOT-WARN' "$WORK/logs/warn.out" | sed 's/^ */    | /' | head -10
}
wcase "clean demo (expect CLEAN, missing_await note)"
cp "$FIX/warn_cases.gd" "$WP/src/_warn.gd"; cp "$FIX/coro_unawaited.gd" "$WP/src/_coro.gd"
wcase "warn_cases + coro_unawaited (expect FOUND 6, none for the coroutines)"
wcase "only src/_coro.gd asked (expect CLEAN + note)" src/_coro.gd
printf '\n[debug]\n\ngdscript/warnings/missing_await=1\n' >> "$WP/project.godot"
wcase "missing_await=1, both files asked (expect FOUND 9)" res://src/_coro.gd res://src/_warn.gd
cp "$WORK/w_project.orig" "$WP/project.godot"
cp "$FIX/syntax_error.gd" "$WP/src/_bad.gd"
s=$(date +%s)
wcase "a syntax error in src/ (expect FAIL at once, no hang)"
echo "    wall=$(( $(date +%s) - s ))s"
rm -f "$WP/src/_bad.gd" "$WP/src/_bad.gd.uid" "$WP/src/_coro.gd" "$WP/src/_coro.gd.uid"
printf '\n[debug]\n\ngdscript/warnings/enable=false\n' >> "$WP/project.godot"
wcase "warnings switched off in project.godot (expect FAIL, not CLEAN)" --no-import
cp "$WORK/w_project.orig" "$WP/project.godot"
# The project in game/ of a repo: `git diff --name-only` paths are repo-relative (game/src/...). Run from the project.
WR="$WORK/warn_repo"; rm -rf "$WR"; mkdir -p "$WR"; cp -r "$WP" "$WR/game"
( cd "$WR/game" && GODOT_BIN="$GODOT_BIN" bash "$WARN" --path . --no-import game/src/_warn.gd > "$WORK/logs/warn.out" 2>&1 )
printf '\n=== KIT warnings.sh: repo-root-relative path game/src/_warn.gd, run in game/ (expect FAIL, not CLEAN)\n    exit=%s\n' $?
tail -1 "$WORK/logs/warn.out" | sed 's/^/    | /'
( cd "$WR/game" && GODOT_BIN="$GODOT_BIN" bash "$WARN" --path . --no-import src/_warn.gd > "$WORK/logs/warn.out" 2>&1 )
printf '\n=== KIT warnings.sh: the same file as src/_warn.gd (expect FOUND 6)\n    exit=%s\n' $?
tail -1 "$WORK/logs/warn.out" | sed 's/^/    | /'
rm -f "$WP/src/_warn.gd" "$WP/src/_warn.gd.uid"

# Kit: gate.sh - the project's gate scene when it has one, else parse_gate_script.gd from the skill as --script.
# GN is a demo copy WITHOUT tools/ (no gate scene, nothing of the kit in it); its scripts name the GameState autoload.
GATESH="$ROOT/skills/godot-headless-harness/gate.sh"; GN="$WORK/gate_none"
rm -rf "$GN"; cp -r "$DEMO" "$GN"; rm -rf "$GN/.godot" "$GN/tools"
gcase() {  # gcase <label> <project> [gate.sh args]
  local label="$1" p="$2"; shift 2
  GODOT_BIN="$GODOT_BIN" bash "$GATESH" --path "$p" "$@" > "$WORK/logs/gate.out" 2>&1
  printf '\n=== KIT gate.sh: %s\n    exit=%s\n' "$label" $?
  grep -E '^gate: |PARSE-GATE|  FAIL  |^GODOT-RUN' "$WORK/logs/gate.out" | sed 's/^ */    | /' | head -5
}
gcase "project without a gate scene (expect script gate, PASS 5 scripts)" "$GN"
cp "$FIX/syntax_error.gd" "$GN/src/_sabotage.gd"
gcase "the same with a syntax error (expect FAIL naming _sabotage.gd)" "$GN"
cp "$FIX/vector2_z.gd" "$GN/src/_sabotage.gd"
gcase "the same with Vector2.ZERO.z (expect FAIL)" "$GN"
rm -f "$GN/src/_sabotage.gd" "$GN/src/_sabotage.gd.uid"
mkdir -p "$GN/addons/thirdparty" "$GN/src/fixtures"; : > "$GN/src/fixtures/.gdignore"
cp "$FIX/syntax_error.gd" "$GN/addons/thirdparty/broken.gd"; cp "$FIX/syntax_error.gd" "$GN/src/fixtures/broken.gd"
gcase "broken scripts only in addons/ and a .gdignore dir (expect PASS)" "$GN"
gcase "--min 99 (expect FAIL: only 5 scripts)" "$GN" --no-import --min 99
gcase "demo with its own gate scene (expect the scene, PASS)" "$WP" --no-import
cp "$FIX/warn_cases.gd" "$GN/src/_warn.gd"
GODOT_BIN="$GODOT_BIN" bash "$WARN" --path "$GN" > "$WORK/logs/warn.out" 2>&1
printf '\n=== KIT warnings.sh on the project without a gate scene, six-warning script (expect FOUND 6)\n    exit=%s\n' $?
grep -E '^  gate: |^GODOT-WARN' "$WORK/logs/warn.out" | sed 's/^ */    | /'
rm -f "$GN/src/_warn.gd" "$GN/src/_warn.gd.uid"

echo; echo "logs: $WORK/logs"
