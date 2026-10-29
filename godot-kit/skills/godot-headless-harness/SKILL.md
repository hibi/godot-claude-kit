---
name: godot-headless-harness
description: Prove that Godot 4 game code works with a headless check that cannot lie - a parse gate (does every GDScript compile?) and diag harness scenes (does the real gameplay code do what we claim?). Use when you add or change GDScript and need to verify it, when asked to write tests, a harness, a smoke check or a CI gate for a Godot project, or before reporting that a fix works. Includes templates and a scaffold script; runs through the godot-run skill.
---

# godot-headless-harness

You get two tools, both of them plain scenes that run headless:

| Tool | Question it answers | Banner |
|---|---|---|
| **parse gate** `res://tools/ci/parse_gate.tscn` | does every script compile, with autoloads live? | `PARSE-GATE: PASS - N scripts, 0 broken` |
| **diag harness** `res://tools/diag_<name>.tscn` | does the REAL code behave as claimed? | `DIAG-<NAME>: PASS n/n` |

Run both with the runner from the `godot-run` skill. It handles isolation, `--import` and `--quit-after`, and its
verdict is the one to trust:

```bash
RUN="${CLAUDE_SKILL_DIR}/../godot-run/godot_run.sh"
bash "$RUN" --path . --banner '^PARSE-GATE: PASS' res://tools/ci/parse_gate.tscn
bash "$RUN" --path . --no-import --banner '^DIAG-HEALTH: PASS' res://tools/diag_health.tscn
```

Pass `--no-import` only to the runs after the first one in a session, while no file was added or moved in between.

**A gate without adding anything to the project:** `gate.sh` runs the project's gate scene if it has one. Otherwise
it runs `parse_gate_script.gd` from this skill's directory as `--script`: the same walk, the same checks, the same
banner. Use it to check a project you should not modify, or before deciding to scaffold.

```bash
bash "${CLAUDE_SKILL_DIR}/gate.sh" --path .              # last line: the runner's GODOT-RUN verdict
bash "${CLAUDE_SKILL_DIR}/gate.sh" --path . --min 40     # script gate: fewer than 40 scripts fails
bash "${CLAUDE_SKILL_DIR}/gate.sh" --path . --include res://addons/my_tool   # script gate: check the add-on you write
```

`ci.sh` (skill `godot-ci`) does the same: it runs the gate scene when there is one, else this script gate, and
`ci.sh install` vendors a copy of the script. Scaffold the scene (section 1) when you want `MIN_SCRIPTS` and the
skipped directories kept in the project itself.

## 1. Put them into the project

```bash
bash "${CLAUDE_SKILL_DIR}/scaffold.sh" --path . gate              # res://tools/ci/parse_gate.gd + .tscn
bash "${CLAUDE_SKILL_DIR}/scaffold.sh" --path . harness enemy_ai  # res://tools/diag_enemy_ai.gd + .tscn
```

- The script writes the `.tscn` itself, so the scene's script path always matches. It never overwrites a file.
- `--dir <project-relative dir>` puts the files somewhere else.
- The templates live in `${CLAUDE_SKILL_DIR}/templates/`.

**After you scaffold the gate:**

1. Run it once.
2. Set `MIN_SCRIPTS` a little under the count its banner printed. With the floor in place, a walk that found nothing,
   or only half the project, can never read as a pass.
3. Add third-party code and broken-on-purpose fixtures to `SKIP`. `res://addons` is already there. A directory that
   holds a `.gdignore` is skipped automatically.
   If the project IS an add-on (its code lives under `res://addons/<name>/`), the gate does not check that code: take
   that directory out of `SKIP` and keep only the third-party ones there (script gate: `gate.sh --include
   res://addons/<name>`; with a gate scene `--include` is refused, so it can never be silently ignored). Measured: an enabled add-on whose script
   does not compile leaves `--headless --editor --quit` at exit 0 with a `SCRIPT ERROR` (trap T18), and the gate
   with `res://addons` skipped says PASS. With the add-on's directory out of `SKIP`, the gate FAILs on it, and a
   correct `@tool extends EditorPlugin` script passes: editor classes compile in the gate's plain scene run (measured
   on 4.4.1 and 4.7.2). Run it on the oldest Godot version you support too.

**After you scaffold a harness:** it fails on purpose until you replace its placeholder with real checks. A harness
that passes before anyone wrote a check is a lie.

## 2. Why the gate runs inside the project

These were measured on Godot 4.7.2 with the kit's `tests/measure_traps.sh` (and on 4.4.1, 4.5.2 and 4.6.3):

- **`--import` does not parse scripts.** A hard syntax error, or `Vector2.ZERO.z`, passes it with exit 0 and no output
  (4.4.1 prints the `SCRIPT ERROR`, but still exits 0).
- **`--check-only --script <file>` lies the other way.** It does catch both errors. But it also fails every
  *correct* script that names an autoload (`Identifier not found: GameState`).
- **Scripts loaded by a running project see the autoloads.** That holds for the gate scene and for the script gate
  run by `gate.sh`. Each gate loads every script fresh (`CACHE_MODE_IGNORE`) and requires it to instantiate. A syntax
  error then shows up as `FAIL res://... (does not compile)` with exit 1. A correct script that names an autoload
  passes.
- **The gate scene skips its own script.** Re-loading the running gate script with `CACHE_MODE_IGNORE` crashed the
  engine (signal 11). The script gate lives outside `res://`, so the walk never reaches it.

## 3. The harness contract

Every rule below exists because breaking it produced a green run that was wrong:

1. **One line per check:** `  ok    <name>` or `  FAIL  <name> (<why>)`. The runner fails on any `FAIL` line, wherever
   it is in the log.
2. **Await every check that awaits.**
   - A fast un-awaited check printed its `FAIL` *after* the `PASS` banner, with exit 0.
   - A slow one (a timer) never printed at all. The engine quit first, so the harness printed `PASS` with exit 0, and
     **even the runner said PASS**. Nothing in the log can catch this.
3. **Assert coverage positively.**
   - `EXPECTED` is the number of checks. The harness itself fails when fewer ran (`FAIL all checks ran (ran 1 of 2)`).
   - This is the only defence against rule 2 going wrong.
   - Update `EXPECTED` in the same edit that adds or removes a check.
4. **Print the banner once, after every check ran, then `quit()`.** Use exit code 1 on any failure.
5. **Drive the real object, never a copy of its logic.**
   - Instantiate the real scene (`preload("res://...tscn").instantiate()` + `add_child`), so `_ready`, `@onready`
     and signals run.
   - Call the real autoload.
   - A check against re-implemented logic only proves the copy works.
6. **Assert the value, not that "something happened".** `hp == 0`, not `hp != 100`. `score == bounty`, not
   `score > 0`. Put the actual values into `<why>`, e.g. `(hp=-30)`, so a FAIL explains itself.
7. **Reset shared state you read.** Autoloads keep their state between checks in one run.
8. **Let the frame settle.** After a signal fan-out, `await get_tree().process_frame` before you assert. After
   `queue_free()`, one frame is not always enough: the demo's check passed locally and failed once on a GitHub
   runner with `alive=true`. Poll instead, with a bound:
   `for i in 10: if not is_instance_valid(e): break; await get_tree().process_frame` (one statement per line).
9. **A lambda captures a local by value.** Both directions compile and run with exit 0:
   - A lambda that assigns a captured local changes only its own copy. `var hits := 0` +
     `hit.connect(func(): hits += 1)` left `hits` at 0 after the signal fired, so `_check("a miss fires no hit",
     hits == 0)` printed `ok`, and the harness printed `PASS` with exit 0.
   - A local reassigned after the lambda was made is not seen by the lambda: it read `aim=1` after `aim = 2`.
   - What a lambda writes, or what changes after the lambda exists, goes into a member variable or a box shared by
     reference. Measured to work: a member (`_fired = true`), `box["hits"] += 1` on a Dictionary, `arr[0] = true` and
     `arr.append(1)` on an Array.

A harness whose own script does not parse leaves the scene running as a bare node. That run exits 0, prints a
`SCRIPT ERROR` and no banner. The runner catches it through the error token and the missing banner. Exit code alone
does not.

## 4. Prove the harness bites: sabotage, one at a time, both directions

A new or changed check is not done until you have seen it fail for the right reason:

1. **Break the code under test, one thing at a time.** For example, remove the clamp in `Health.damage`. Then run
   the harness and expect **exactly** the check that guards that behaviour to FAIL, with the wrong value in `<why>`.
   Measured on the demo: `FAIL damage clamps at 0 (hp=-30)`, exit 1, and the other checks stay `ok`.
2. **Restore the code** byte for byte. Copy the original aside first and compare with `cmp`; never trust an undo from
   memory. Then run again and expect PASS.
3. If the check stayed `ok` while the code was broken, the check is worthless. Fix the check, not the sabotage.

Do the same for the parse gate: drop a file with a syntax error into a scanned directory, expect `FAIL ... (does not
compile)`, then delete it. Keep fixtures that are broken on purpose outside the scanned directories (or in `SKIP`), and
never leave one behind.

## 5. GDScript warnings

The gate answers "does it compile". The engine's GDScript warnings answer "does it do what it looks like": an unused
variable, a shadowed one, integer division, a standalone expression, unreachable code. Measured on Godot 4.7.2 (and
4.5.2, 4.6.3; `warnings.sh` needs 4.5 or later - 4.4.1 prints the warnings as `ERROR: '<message>'` lines without
file or line, and `warnings.sh` then FAILs):

- **Without `--debug` the engine prints no warnings at all.** `--check-only` exits 0 silently, and the gate says PASS.
- **With `--debug`, a script that does not parse stops at a `debug>` prompt.**
  - On Windows the engine never exits, even with stdin closed; both `--check-only` and the gate hung.
  - On Linux, with stdin closed, `--check-only` crashed (exit 132), and the gate went on and failed normally.
- **An un-awaited call to a coroutine** (`slow()` where `slow` contains `await`) warns only when the project enables
  `debug/gdscript/warnings/missing_await`, and that setting is **off** by default. On 4.4.1 and 4.5.2 it gives no
  warning even when enabled (4.6.3 and 4.7.2 do). Using such a call's return value
  without `await` is a parse error, so the gate catches that case.
- **A lambda that assigns a captured local** (rule 9 of section 3) warns with `--debug`: `Reassigning lambda capture
  does not modify the outer local variable "hits"`. The other direction, a local reassigned after the lambda was
  made, gives no warning with the default warning settings.

`warnings.sh` handles all three:

```bash
bash "${CLAUDE_SKILL_DIR}/warnings.sh" --path .                          # whole project
bash "${CLAUDE_SKILL_DIR}/warnings.sh" --path . src/player.gd src/hud.gd  # only what you changed
```

1. It runs the gate normally: the project's gate scene, or the script gate when there is none (see the top).
2. Only after a PASS does it run the gate again with `--debug`, under a wall-clock timeout.
3. It prints each warning as `res://file.gd:LINE: message`, skipping `res://addons/`.
4. If `missing_await` is off, or the engine is older than 4.6, it adds a note saying so. Un-awaited coroutine calls
   then have to be checked by hand.

| Last line | Exit | Meaning |
|---|---|---|
| `GODOT-WARN: CLEAN (...)` | 0 | no warning in the files asked (or the whole project) |
| `GODOT-WARN: FOUND n (...)` | 1 | n warnings, listed above it |
| `GODOT-WARN: FAIL (why)` | 2 | could not check: the gate failed, the `--debug` run did not finish, a file is not in the project, or warnings are off |
| `GODOT-WARN: NO-ENGINE` | 3 | no binary |

The project's own warning settings apply. A warning the project set to "error" fails the gate, like any parse error.

## 6. Reporting

When you report, include:

- each runner verdict line;
- the `ok` / `FAIL` lines;
- the banner;
- for a new check, the sabotage run that made it FAIL and the restored run that made it PASS.

"The harness passes" without the sabotage evidence means only that the harness ran.
