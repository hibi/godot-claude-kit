#!/usr/bin/env bash
# scaffold.sh - put a new two-process multiplayer harness into a Godot 4 project, from this skill's template.
#
#   bash scaffold.sh --path <project> <name>    -> res://tools/netdiag_<name>.gd + .tscn, banners NETDIAG-<NAME>-SERVER/CLIENT
#
#   --dir D   project-relative directory to write into (default tools)
#
# Writes the .tscn itself, so its script path always matches where the .gd landed. Never overwrites a file.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

PROJECT="" DIR="tools" ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PROJECT="$2"; shift 2 ;;
    --dir) DIR="${2%/}"; DIR="${DIR#res://}"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}
[ -n "$PROJECT" ] && [ -f "$PROJECT/project.godot" ] || { echo "scaffold: no project.godot in --path '$PROJECT'"; exit 1; }
name="${1:-}"
case "$name" in
  ''|*[!a-z0-9_]*) echo "usage: bash scaffold.sh --path <project> <name>   (name: lower-case [a-z0-9_], got '$name')"; exit 1 ;;
esac

NAME=$(printf '%s' "$name" | tr 'a-z' 'A-Z')
gd="$PROJECT/$DIR/netdiag_$name.gd"; tscn="$PROJECT/$DIR/netdiag_$name.tscn"
for f in "$gd" "$tscn"; do [ -e "$f" ] && { echo "scaffold: $f already exists - not overwriting"; exit 1; }; done
mkdir -p "$PROJECT/$DIR"
sed -e "s|__NAME__|$NAME|g" -e "s|__name__|$name|g" -e "s|__DIR__|$DIR|g" "$HERE/templates/netdiag_template.gd" > "$gd"
node=$(printf '%s' "$name" | awk -F_ '{ for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2) }')
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://%s" id="1"]\n\n[node name="Netdiag%s" type="Node"]\nscript = ExtResource("1")\n' \
  "$DIR/netdiag_$name.gd" "$node" > "$tscn"
echo "wrote res://$DIR/netdiag_$name.gd and res://$DIR/netdiag_$name.tscn (banners NETDIAG-$NAME-SERVER / -CLIENT)"
echo "next: it FAILS on both sides until the placeholders are replaced by real checks and EXPECTED matches them."
