#!/usr/bin/env bash
# net_run.sh - run a two-process multiplayer harness headless: ONE server and N clients, each its own isolated engine
# judged by godot_run.sh, and PASS only when EVERY process passed. An RPC error lands in one side's log only (the
# sender's for a call to a non-@rpc function, the receiver's for a node path the other side does not have), so
# judging one log - or the exit codes, which stay 0 - misses it.
#
#   bash net_run.sh --path <project> [options] res://tools/netdiag_<name>.tscn
#
#   --clients N      clients to start (default 1); the server gets --clients=N too
#   --port P         UDP port (default: a random one in 20000-49999)
#   --frames N, --timeout S   passed to every run. Defaults --timeout 120 (a hung peer must not hold CI for 10 min)
#                    and --frames 100000: the harness waits are in SECONDS, and the runner's default 3600 frames (~25 s
#                    headless) could cut a harness with several waits mid-failure - the wall timeout is the backstop
#   --no-import      skip the one import before the processes start (only when the .godot/ cache is current)
#   --out DIR        keep the logs here (default: a fresh temp dir; printed either way)
#
# Each process gets the user args `-- --role=server|client --port=P --clients=N [--client=i]`.
# Banners: NETDIAG-<NAME>-SERVER: PASS / NETDIAG-<NAME>-CLIENT: PASS (scene res://.../netdiag_<name>.tscn).
#
# Last line and exit code:
#   GODOT-NET: PASS (server + N client(s))   0
#   GODOT-NET: FAIL (<roles that failed>)    1
#   GODOT-NET: NO-ENGINE                     3
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

PROJECT="" CLIENTS=1 PORT="" DO_IMPORT=1 OUT="" RUNARGS=(--timeout 120 --frames 100000) SCENE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PROJECT="${2%/}"; shift 2 ;;
    --clients) CLIENTS="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --frames|--timeout) RUNARGS+=("$1" "$2"); shift 2 ;;
    --no-import) DO_IMPORT=0; shift ;;
    --out) OUT="$2"; shift 2 ;;
    res://*) SCENE="$1"; shift ;;
    *) echo "GODOT-NET: FAIL (unknown argument '$1')"; exit 1 ;;
  esac
done
[ -n "$PROJECT" ] && [ -f "$PROJECT/project.godot" ] || { echo "GODOT-NET: FAIL (no project.godot in --path '$PROJECT')"; exit 1; }
base=$(basename "${SCENE:-x}" .tscn)
case "$base" in
  netdiag_*) ;;
  *) echo "GODOT-NET: FAIL (scene must be res://.../netdiag_<name>.tscn, got '$SCENE')"; exit 1 ;;
esac
[ -f "$PROJECT/${SCENE#res://}" ] || { echo "GODOT-NET: FAIL ($SCENE does not exist)"; exit 1; }
NAME=$(printf '%s' "${base#netdiag_}" | tr 'a-z' 'A-Z')

# The runner: next to this script when vendored into a project, else the sibling godot-run skill.
RUNNER="$HERE/godot_run.sh"
[ -f "$RUNNER" ] || RUNNER="$HERE/../godot-run/godot_run.sh"
[ -f "$RUNNER" ] || { echo "GODOT-NET: FAIL (godot_run.sh not found next to net_run.sh or in ../godot-run/)"; exit 1; }

[ -n "$PORT" ] || PORT=$((20000 + (RANDOM * 32768 + RANDOM) % 30000))
[ -n "$OUT" ] || OUT=$(mktemp -d "${TMPDIR:-/tmp}/godot_net.XXXXXX")
mkdir -p "$OUT"
show_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

# One import up front: every process below starts with --no-import, so they never write .godot/ at the same time.
if [ "$DO_IMPORT" = 1 ]; then
  bash "$RUNNER" --path "$PROJECT" --import-only > "$OUT/import.runner" 2>&1
  rc=$?
  [ $rc -eq 3 ] && { cat "$OUT/import.runner"; echo "GODOT-NET: NO-ENGINE (set GODOT_BIN to the Godot 4 executable)"; exit 3; }
  [ $rc -eq 0 ] || { sed 's/^/   /' "$OUT/import.runner"; echo "GODOT-NET: FAIL (import)"; exit 1; }
fi

echo "net:     $SCENE, server + $CLIENTS client(s) on 127.0.0.1:$PORT, logs $(show_path "$OUT")"
start() {  # start <tag> <role> [extra user args...]  -> background runner, output in $OUT/<tag>.runner
  local tag="$1" role="$2"; shift 2
  local banner="^NETDIAG-$NAME-$(printf '%s' "$role" | tr 'a-z' 'A-Z'): PASS"
  bash "$RUNNER" --path "$PROJECT" --no-import --banner "$banner" --log "$OUT/$tag.log" "${RUNARGS[@]}" \
    "$SCENE" -- --role="$role" --port="$PORT" --clients="$CLIENTS" "$@" > "$OUT/$tag.runner" 2>&1 &
  PIDS+=($!); TAGS+=("$tag")
}
PIDS=() TAGS=()
# Server first; clients right after - ENet keeps retrying a client that knocks before the server listens.
start server server
for i in $(seq 1 "$CLIENTS"); do start "client$i" client --client="$i"; done

failed=() noengine=0
for ((k = 0; k < ${#PIDS[@]}; k++)); do
  wait "${PIDS[$k]}"; rc=$?
  tag="${TAGS[$k]}"
  echo "== $tag"
  sed 's/^/   /' "$OUT/$tag.runner"
  [ $rc -eq 3 ] && noengine=1
  [ $rc -eq 0 ] || failed+=("$tag")
done

[ $noengine = 1 ] && { echo "GODOT-NET: NO-ENGINE (set GODOT_BIN to the Godot 4 executable)"; exit 3; }
if [ ${#failed[@]} -gt 0 ]; then echo "GODOT-NET: FAIL (${failed[*]})"; exit 1; fi
echo "GODOT-NET: PASS (server + $CLIENTS client(s))"
exit 0
