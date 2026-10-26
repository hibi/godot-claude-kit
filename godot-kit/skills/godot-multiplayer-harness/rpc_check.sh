#!/usr/bin/env bash
# rpc_check.sh - static check: does every RPC the project SENDS have an @rpc function to land on?
#
#   bash rpc_check.sh --path <project>
#
# Why: `foo.rpc()` / `rpc_id(1, "foo")` on a function without @rpc compiles - the parse gate passes it - and fails
# only at run time, with an ERROR in the SENDER's log alone; the receiver never hears of it and both exit 0.
#
# What it reads (GDScript outside .godot/ and .gdignore directories):
#   declared:  `@rpc(...)` on the line above `func NAME` or on the same line, and `rpc_config("NAME", ...)` -
#              in addons/ too, because game code may call an addon's RPCs
#   sent:      `NAME.rpc(` / `NAME.rpc_id(` when NAME is a func of the project (Callable form), else the string at the
#              method position of `x.rpc("NAME", ...)` / `x.rpc_id(id, "NAME", ...)` / bare `rpc("NAME")` (also &"NAME");
#              calls inside addons/ are not checked - third-party code is not yours to fail
# Limits - it works BY NAME: the same method name declared @rpc in another class satisfies it, and a method name kept
# in a variable or built at run time is not seen (such calls are skipped, not guessed). `ci.sh --no-rpc-check` turns
# the check off for a project it misreads.
#
# Last line and exit code:  RPC-CHECK: PASS - ... 0  |  RPC-CHECK: FAIL - N unknown ... 1
set -u
PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PROJECT="${2%/}"; shift 2 ;;
    *) echo "RPC-CHECK: FAIL - unknown argument '$1'"; exit 1 ;;
  esac
done
[ -n "$PROJECT" ] && [ -f "$PROJECT/project.godot" ] || { echo "RPC-CHECK: FAIL - no project.godot in --path '$PROJECT'"; exit 1; }

gdignored() {  # is any directory between the file and the project root marked with .gdignore?
  local d; d=$(dirname "$1")
  while [ "$d" != "$PROJECT" ] && [ "$d" != "." ] && [ "$d" != "/" ]; do
    [ -e "$d/.gdignore" ] && return 0
    d=$(dirname "$d")
  done
  return 1
}
FILES=()
while IFS= read -r f; do gdignored "$f" || FILES+=("$f"); done < <(
  find "$PROJECT" \( -path "$PROJECT/.godot" -o -name .git \) -prune \
    -o -type f -name '*.gd' -print | sort)
[ ${#FILES[@]} -gt 0 ] || { echo "RPC-CHECK: PASS - no GDScript files"; exit 0; }

# Plain POSIX awk (mawk on Debian, gawk in Git Bash): match() with RSTART/RLENGTH only. The project root goes in
# through ENVIRON, not -v: -v processes escapes, and a Windows path (C:\Users\...) came out mangled.
RPC_CHECK_ROOT="$PROJECT/" awk '
function res(f) { return "res://" substr(f, length(ENVIRON["RPC_CHECK_ROOT"]) + 1) }
function decl(s,   n) {  # s contains "func NAME" -> NAME
  if (match(s, /func[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
    n = substr(s, RSTART, RLENGTH); sub(/^func[ \t]+/, "", n); return n
  }
  return ""
}
FNR == 1 { pend = 0; declonly = (index(substr(FILENAME, length(ENVIRON["RPC_CHECK_ROOT"]) + 1), "addons/") == 1) }
{
  # Drop the comment (everything from a # outside a string). `mask` is the same line with string contents blanked,
  # so text inside a string never reads as a call; method names are then taken from the real line, same offsets.
  line = $0; out = ""; mask = ""; q = ""
  for (i = 1; i <= length(line); i++) {
    c = substr(line, i, 1)
    if (q == "") {
      if (c == "#") break
      if (c == "\"" || c == "\047") q = c
      m = c
    } else {
      if (c == q && substr(line, i - 1, 1) != "\\") { q = ""; m = c } else m = " "
    }
    out = out c; mask = mask m
  }
  line = out

  n = decl(line)
  if (n != "") funcs[n] = 1
  if (line ~ /@rpc/) {
    if (n != "") rpcs[n] = 1; else pend = 1
  } else if (pend) {
    if (n != "") { rpcs[n] = 1; pend = 0 }
    else if (line !~ /^[ \t]*(@.*)?$/) pend = 0   # anything but blank lines and other annotations ends it
  }
  s = mask; off = 0                                 # rpc_config("NAME", {...}) declares NAME without an annotation
  while (match(s, /rpc_config\(/)) {
    rest = substr(line, off + RSTART + RLENGTH)
    off += RSTART + RLENGTH - 1
    s = substr(s, RSTART + RLENGTH)
    if (match(rest, /^[ \t]*&?"[A-Za-z_][A-Za-z0-9_]*"/)) { n = substr(rest, RSTART, RLENGTH); gsub(/[ \t"&]/, "", n); rpcs[n] = 1 }
  }
  if (declonly) next

  s = mask; off = 0
  while (match(s, /([A-Za-z_][A-Za-z0-9_]*\.)?rpc(_id)?\(/)) {
    tok = substr(s, RSTART, RLENGTH); before = (RSTART > 1) ? substr(s, RSTART - 1, 1) : ""
    rest = substr(line, off + RSTART + RLENGTH)            # the real text after "rpc(" (strings intact)
    off += RSTART + RLENGTH - 1
    s = substr(s, RSTART + RLENGTH)
    ident = ""
    if (index(tok, ".") > 0) { ident = substr(tok, 1, index(tok, ".") - 1) }
    else if (before ~ /[A-Za-z0-9_.@]/) continue         # part of a longer name (my_rpc), or the @rpc annotation
    args = rest
    if (tok ~ /rpc_id\($/) {                              # skip the peer id argument
      if (match(args, /^[^,()]*,[ \t]*/)) args = substr(args, RLENGTH + 1); else args = ""
    }
    lit = ""
    if (match(args, /^[ \t]*&?"[A-Za-z_][A-Za-z0-9_]*"/)) { lit = substr(args, RSTART, RLENGTH); gsub(/[ \t"&]/, "", lit) }
    calls++
    cfile[calls] = FILENAME; cline[calls] = FNR; cident[calls] = ident; clit[calls] = lit
    ctext[calls] = tok
  }
}
END {
  bad = 0; seen = 0; skipped = 0
  for (k = 1; k <= calls; k++) {
    id = cident[k]
    if (id != "" && id in funcs) method = id                       # Callable form: foo.rpc(...)
    else if (id == "multiplayer") { skipped++; continue }          # MultiplayerAPI.rpc(peer, object, method, ...)
    else method = clit[k]                                          # object form: x.rpc("foo") / rpc("foo")
    if (method == "") { skipped++; continue }
    seen++
    if (!(method in rpcs)) {
      bad++
      printf "  FAIL  %s:%d  %s -> no @rpc func %s in the project\n", res(cfile[k]), cline[k], ctext[k], method
    }
  }
  nr = 0; for (r in rpcs) nr++
  note = skipped ? sprintf(", %d with a method name not known statically (skipped)", skipped) : ""
  if (bad) printf "RPC-CHECK: FAIL - %d of %d rpc call(s) name no @rpc function (%d @rpc functions%s)\n", bad, seen, nr, note
  else printf "RPC-CHECK: PASS - %d rpc call(s), all land on one of %d @rpc functions%s\n", seen, nr, note
  exit bad ? 1 : 0
}
' "${FILES[@]}"
