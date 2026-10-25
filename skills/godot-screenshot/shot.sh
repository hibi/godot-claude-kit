#!/usr/bin/env bash
# shot.sh - render ONE frame of a scene to a PNG in a real (off-screen) window, judge it, and optionally compare it
# with a golden image. --headless cannot do this: it never draws a frame (frame_post_draw never fires, the viewport
# texture is null, --write-movie crashes), and all three exit 0.
#
#   bash shot.sh --path <project> --out <file.png> [options]
#
#   --scene res://x.tscn  scene to shoot (default: the project's main scene)
#   --size WxH            window and image size (default 1280x720); the image is checked against it
#   --settle N            frames to let the scene run before the capture (default 10; raise for intros/tweens)
#   --driver D            --rendering-driver (vulkan / opengl3 / d3d12 ...). Default: the project's, except opengl3
#                         under xvfb, where Vulkan on llvmpipe crashed (signal 11) when measured
#   --golden FILE.png     compare with this golden (needs FILE.json next to it, written by --update-golden)
#   --max-rmse F          allowed root-mean-square difference vs the golden, 0-255 scale (default 0.5). Measured: the
#                         same driver + GPU renders 0.000 run to run; one changed digit in a 32 px label is 1.39
#   --update-golden       write --golden FILE.png + FILE.json from this run (only when the frame itself passed)
#   --allow-engine-errors, --timeout S, --no-import   passed to the runner
#
# The capture runs as `--script` from this skill's directory: no script or scene is added to the project (the import
# writes its usual .godot/ cache).
# Display: Windows (macOS untested) - a normal window placed off-screen. Linux - $DISPLAY / $WAYLAND_DISPLAY if set, else xvfb-run
# if installed, else NO-DISPLAY.
#
# Last line and exit code:
#   GODOT-SHOT: PASS <png>          0   frame drawn, right size, not blank, no engine error; golden matched if given
#   GODOT-SHOT: FAIL (why)          1
#   GODOT-SHOT: UNVERIFIED (why)    2   frame fine, but the golden was rendered by another driver/GPU: not compared
#   GODOT-SHOT: NO-ENGINE           3   set GODOT_BIN
#   GODOT-SHOT: NO-DISPLAY          4   Linux without a display or xvfb-run: nothing can be rendered here
# PASS proves the frame is not broken, not that it looks RIGHT: open the PNG and look at it.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

PROJECT="" OUT="" SCENE="" SIZE=1280x720 SETTLE=10 DRIVER="" GOLDEN="" MAX_RMSE=0.5 UPDATE=0 RUNARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PROJECT="${2%/}"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --scene) SCENE="$2"; shift 2 ;;
    --size) SIZE="$2"; shift 2 ;;
    --settle) SETTLE="$2"; shift 2 ;;
    --driver) DRIVER="$2"; shift 2 ;;
    --golden) GOLDEN="$2"; shift 2 ;;
    --max-rmse) MAX_RMSE="$2"; shift 2 ;;
    --update-golden) UPDATE=1; shift ;;
    --allow-engine-errors|--no-import) RUNARGS+=("$1"); shift ;;
    --timeout) RUNARGS+=("$1" "$2"); shift 2 ;;
    *) echo "GODOT-SHOT: FAIL (unknown argument '$1')"; exit 1 ;;
  esac
done
[ -n "$PROJECT" ] && [ -f "$PROJECT/project.godot" ] || { echo "GODOT-SHOT: FAIL (no project.godot in --path '$PROJECT')"; exit 1; }
case "$OUT" in *.png|*.PNG) ;; *) echo "GODOT-SHOT: FAIL (--out <file.png> is required, got '$OUT')"; exit 1 ;; esac
case "$SIZE" in *[0-9]x[0-9]*) ;; *) echo "GODOT-SHOT: FAIL (--size must be WxH, got '$SIZE')"; exit 1 ;; esac
[ "$UPDATE" = 1 ] && [ -z "$GOLDEN" ] && { echo "GODOT-SHOT: FAIL (--update-golden needs --golden FILE.png)"; exit 1; }
if [ -z "$SCENE" ]; then
  SCENE=$(sed -n 's/^run\/main_scene="\(.*\)"/\1/p' "$PROJECT/project.godot" | tr -d '\r')
  [ -n "$SCENE" ] || { echo "GODOT-SHOT: FAIL (no --scene and no run/main_scene in project.godot)"; exit 1; }
fi

RUNNER="$HERE/godot_run.sh"
[ -f "$RUNNER" ] || RUNNER="$HERE/../godot-run/godot_run.sh"
[ -f "$RUNNER" ] || { echo "GODOT-SHOT: FAIL (godot_run.sh not found next to shot.sh or in ../godot-run/)"; exit 1; }

# The engine gets absolute, native paths (on Windows C:/...): the capture script is outside res://.
abs() { local d; d=$(cd "$(dirname "$1")" 2>/dev/null && pwd) || return 1; echo "$d/$(basename "$1")"; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
mkdir -p "$(dirname "$OUT")"
OUT_N=$(native "$(abs "$OUT")")
GOLDEN_N=""
if [ -n "$GOLDEN" ]; then
  gdir=$(dirname "$GOLDEN")
  if [ "$UPDATE" = 1 ]; then
    mkdir -p "$gdir"
    # Goldens inside the project need a .gdignore, or the editor imports every PNG as a texture into .godot/.
    case "$(cd "$gdir" && pwd)/" in
      "$(cd "$PROJECT" && pwd)"/*)
        [ -e "$gdir/.gdignore" ] || { : > "$gdir/.gdignore"; echo "shot:    wrote $gdir/.gdignore (keeps the goldens out of the import)"; } ;;
    esac
  fi
  [ -d "$gdir" ] || { echo "GODOT-SHOT: FAIL (golden directory $gdir does not exist - create goldens with --update-golden)"; exit 1; }
  GOLDEN_N=$(native "$(abs "$GOLDEN")")
  # The frame is written to --out before the golden is read: one file for both would compare the frame with itself.
  # (Windows paths are case-insensitive, so compare them lower-cased there.)
  same() { if command -v cygpath >/dev/null 2>&1; then printf '%s' "$1" | tr 'A-Z' 'a-z'; else printf '%s' "$1"; fi; }
  if [ "$(same "$GOLDEN_N")" = "$(same "$OUT_N")" ]; then
    echo "GODOT-SHOT: FAIL (--out and --golden are the same file: the golden would be overwritten by the frame it is checking)"
    exit 1
  fi
fi

# --audio-driver Dummy: a screenshot needs no sound, and a CI runner with ALSA but no sound card logs
# `ERROR: ... ERR_CANT_OPEN` (init_output_device) on every drawing run - a good frame would FAIL on it. Measured.
WRAP=() ENGINE_ARGS=(--resolution "$SIZE" --audio-driver Dummy)
if [ "$(uname -s)" = Linux ]; then
  if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    if command -v xvfb-run >/dev/null 2>&1; then
      WRAP=(xvfb-run -a -s "-screen 0 ${SIZE}x24")
      [ -n "$DRIVER" ] || DRIVER=opengl3
    else
      echo "GODOT-SHOT: NO-DISPLAY (Linux without \$DISPLAY and without xvfb-run; install xvfb, or run on a desktop)"
      exit 4
    fi
  fi
else
  # A real window, parked off-screen so it does not flash over the user's work. Measured: it still renders.
  ENGINE_ARGS+=(--position -10000,-10000)
fi
[ -n "$DRIVER" ] && ENGINE_ARGS+=(--rendering-driver "$DRIVER")

USER_ARGS=(--scene="$SCENE" --out="$OUT_N" --size="$SIZE" --settle="$SETTLE")
if [ -n "$GOLDEN_N" ]; then
  USER_ARGS+=(--golden="$GOLDEN_N" --max-rmse="$MAX_RMSE")
  [ "$UPDATE" = 1 ] && USER_ARGS+=(--update-golden)
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/godot_shot.XXXXXX")
LOG="$WORK/shot.log"
rm -f "$OUT"  # a stale PNG from an earlier run must never pass for this one
echo "shot:    $SCENE at $SIZE${DRIVER:+, driver $DRIVER}${WRAP:+, under xvfb-run}"
${WRAP[@]+"${WRAP[@]}"} bash "$RUNNER" --path "$PROJECT" --windowed --banner '^SHOT: PASS' --frames $((SETTLE + 600)) \
  --log "$LOG" ${RUNARGS[@]+"${RUNARGS[@]}"} -- "${ENGINE_ARGS[@]}" --script "$(native "$HERE/shot_capture.gd")" \
  ++ "${USER_ARGS[@]}" > "$WORK/runner.out" 2>&1
rc=$?
cp "$LOG" "${OUT%.*}.log" 2>/dev/null  # the run log next to the PNG: a CI artifact then carries both
cat "$WORK/runner.out"
[ $rc -eq 3 ] && { echo "GODOT-SHOT: NO-ENGINE (set GODOT_BIN to the Godot 4 executable)"; exit 3; }
CLEAN=$(tr -d '\r' < "$LOG" 2>/dev/null)
printf '%s\n' "$CLEAN" | grep -E '^(shot|golden): ' | sed 's/^/  /'
if [ $rc -ne 0 ]; then
  why=$(grep '^GODOT-RUN: FAIL' "$WORK/runner.out" | sed 's/^GODOT-RUN: FAIL (\(.*\))$/\1/' | head -1)
  first=$(printf '%s\n' "$CLEAN" | grep -m1 '^FAIL ' | sed 's/^FAIL //')
  echo "GODOT-SHOT: FAIL (${first:-${why:-runner exit $rc}})"
  exit 1
fi
[ -s "$OUT" ] || { echo "GODOT-SHOT: FAIL (banner seen but $OUT was not written)"; exit 1; }
skip=$(printf '%s\n' "$CLEAN" | grep -m1 '^golden: SKIPPED' | sed 's/^golden: SKIPPED compare - //')
if [ -n "$skip" ]; then
  echo "GODOT-SHOT: UNVERIFIED (golden not compared: $skip) $OUT_N"
  exit 2
fi
echo "GODOT-SHOT: PASS $OUT_N"
