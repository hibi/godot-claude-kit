#!/usr/bin/env bash
# scaffold.sh - put the parse gate or a new harness into a Godot 4 project, from this skill's templates.
#
#   bash scaffold.sh --path <project> gate              -> res://tools/ci/parse_gate.gd + .tscn
#   bash scaffold.sh --path <project> harness <name>    -> res://tools/diag_<name>.gd + .tscn, banner DIAG-<NAME>
#
#   --dir D   project-relative directory to write into (default tools/ci for the gate, tools for a harness)
#
# Writes the .tscn itself, so its script path always matches where the .gd landed. Never overwrites a file.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

PROJECT="" DIR="" ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PROJECT="$2"; shift 2 ;;
    --dir) DIR="${2%/}"; DIR="${DIR#res://}"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}
[ -n "$PROJECT" ] && [ -f "$PROJECT/project.godot" ] || { echo "scaffold: no project.godot in --path '$PROJECT'"; exit 1; }
KIND="${1:-}"

write_scene() {  # write_scene <res path of the .gd> <node name> <out file>
  printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="%s" id="1"]\n\n[node name="%s" type="Node"]\nscript = ExtResource("1")\n' \
    "$1" "$2" > "$3"
}
refuse_existing() {
  for f in "$@"; do [ -e "$f" ] && { echo "scaffold: $f already exists - not overwriting"; exit 1; }; done
  return 0
}

case "$KIND" in
  gate)
    DIR="${DIR:-tools/ci}"
    gd="$PROJECT/$DIR/parse_gate.gd"; tscn="$PROJECT/$DIR/parse_gate.tscn"
    refuse_existing "$gd" "$tscn"
    mkdir -p "$PROJECT/$DIR"
    cp "$HERE/templates/parse_gate.gd" "$gd"
    write_scene "res://$DIR/parse_gate.gd" "ParseGate" "$tscn"
    echo "wrote res://$DIR/parse_gate.gd and res://$DIR/parse_gate.tscn"
    echo "next: run it, then set MIN_SCRIPTS a little under the count the banner prints; add broken-on-purpose"
    echo "      fixture directories and third-party code to SKIP."
    ;;
  harness)
    name="${2:-}"
    case "$name" in ''|*[!a-z0-9_]*) echo "scaffold: harness name must be lower-case [a-z0-9_], got '$name'"; exit 1 ;; esac
    DIR="${DIR:-tools}"
    NAME=$(printf '%s' "$name" | tr 'a-z' 'A-Z')
    gd="$PROJECT/$DIR/diag_$name.gd"; tscn="$PROJECT/$DIR/diag_$name.tscn"
    refuse_existing "$gd" "$tscn"
    mkdir -p "$PROJECT/$DIR"
    sed -e "s|__NAME__|$NAME|g" -e "s|__name__|$name|g" -e "s|__DIR__|$DIR|g" "$HERE/templates/diag_template.gd" > "$gd"
    node=$(printf '%s' "$name" | awk -F_ '{ for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2) }')
    write_scene "res://$DIR/diag_$name.gd" "Diag$node" "$tscn"
    echo "wrote res://$DIR/diag_$name.gd and res://$DIR/diag_$name.tscn (banner DIAG-$NAME)"
    echo "next: it FAILS until the placeholder is replaced by real checks and EXPECTED matches their number."
    ;;
  *)
    echo "usage: bash scaffold.sh --path <project> gate | harness <name>  [--dir <project-relative dir>]"; exit 1 ;;
esac
