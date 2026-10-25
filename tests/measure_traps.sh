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
    powershell.exe -NoProfile -Command "\$exe='$(cygpath -w "$GUI_EXE")'; \$sw=[Diagnostics.Stopwatch]::StartNew(); & \$exe --headless --path '$(cygpath -w "$DEMO")' --quit-after 600 res://tools/diag_health.tscn *> '$(cygpath -w "$WORK/logs/t9_raw.log")'; \$ms=\$sw.ElapsedMilliseconds; \$still=@(Get-Process | Where-Object { \$_.Path -eq \$exe }).Count; \"returned_ms=\$ms exit='\$LASTEXITCODE' still_running=\$still\"; Get-Process | Where-Object { \$_.Path -eq \$exe } | Wait-Process" > "$ps_log" 2>&1
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
ci_case "gate scene missing (expect FAIL: gate; diag_health still PASS)" "rm tools/ci/parse_gate.tscn"
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

echo; echo "logs: $WORK/logs"
