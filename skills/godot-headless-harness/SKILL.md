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

**After you scaffold a harness:** it fails on purpose until you replace its placeholder with real checks. A harness
that passes before anyone wrote a check is a lie.

## 2. Why the gate is a scene

These were measured on Godot 4.7.2 with the kit's `tests/measure_traps.sh`:

- **`--import` does not parse scripts.** A hard syntax error, or `Vector2.ZERO.z`, passes it with exit 0 and no output.
- **`--check-only --script <file>` lies the other way.** It does catch both errors. But it also fails every
  *correct* script that names an autoload (`Identifier not found: GameState`). The script handed to `--script` is
  compiled before the project's autoload names exist; scenes loaded later in such a run do see them.
- **In a scene the autoloads are live.** The gate loads every script fresh (`CACHE_MODE_IGNORE`) and requires it to
  instantiate. A syntax error then shows up as `FAIL res://... (does not compile)` with exit 1.
- **The gate skips its own script.** Re-loading the running gate script with `CACHE_MODE_IGNORE` crashed the engine
  (signal 11).

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
8. **Let the frame settle.** After `queue_free()` or a signal fan-out, `await get_tree().process_frame` before you
   assert.

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
variable, a shadowed one, integer division, a standalone expression, unreachable code. Measured on Godot 4.7.2:

- **Without `--debug` the engine prints no warnings at all.** `--check-only` exits 0 silently, and the gate says PASS.
- **With `--debug`, a script that does not parse stops at a `debug>` prompt.**
  - On Windows the engine never exits, even with stdin closed; both `--check-only` and the gate hung.
  - On Linux, with stdin closed, `--check-only` crashed (exit 132), and the gate went on and failed normally.
- **An un-awaited call to a coroutine** (`slow()` where `slow` contains `await`) warns only when the project enables
  `debug/gdscript/warnings/missing_await`, and that setting is **off** by default. Using such a call's return value
  without `await` is a parse error, so the gate catches that case.

`warnings.sh` handles all three:

```bash
bash "${CLAUDE_SKILL_DIR}/warnings.sh" --path .                          # whole project
bash "${CLAUDE_SKILL_DIR}/warnings.sh" --path . src/player.gd src/hud.gd  # only what you changed
```

1. It runs the gate normally.
2. Only after a PASS does it run the gate again with `--debug`, under a wall-clock timeout.
3. It prints each warning as `res://file.gd:LINE: message`, skipping `res://addons/`.
4. If `missing_await` is off, it adds a note saying so. Un-awaited coroutine calls then have to be checked by hand.

| Last line | Exit | Meaning |
|---|---|---|
| `GODOT-WARN: CLEAN (...)` | 0 | no warning in the files asked (or the whole project) |
| `GODOT-WARN: FOUND n (...)` | 1 | n warnings, listed above it |
| `GODOT-WARN: FAIL (why)` | 2 | could not check: no gate, the gate failed, or the `--debug` pass did not finish |
| `GODOT-WARN: NO-ENGINE` | 3 | no binary |

The project's own warning settings apply. A warning the project set to "error" fails the gate, like any parse error.

## 6. Reporting

When you report, include:

- each runner verdict line;
- the `ok` / `FAIL` lines;
- the banner;
- for a new check, the sabotage run that made it FAIL and the restored run that made it PASS.

"The harness passes" without the sabotage evidence means only that the harness ran.
