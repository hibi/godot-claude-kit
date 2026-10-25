# godot-claude-kit

**Claude Code skills that make Claude actually run, test and verify a Godot 4 project, instead of trusting an exit
code.**

When an AI agent "verifies" a Godot change, it usually runs the engine headless, sees exit code 0 and reports success.
In Godot 4 that proves nothing. Every row below exits **0**:

| What happened | Exit | What the log shows |
|---|---|---|
| `--import` on a project with a hard syntax error | 0 | nothing at all |
| a scene whose own script does not parse | 0 | `SCRIPT ERROR`, then the scene runs as a bare node |
| a test harness that forgot to `await` a slow check | 0 | `PASS`, and the failing check never prints |
| a run with `--user-data-dir` (Godot 4 has no such flag) | 0 | empty: the scene never ran |
| a fresh clone run before `--import` | 0 | a false `Could not find type "<ClassName>"` |
| a healthy scene that simply prints nothing | 0 | byte-identical to the "never ran" log above |

There are also false alarms. For example, `--check-only --script` fails every *correct* script that uses an autoload.

This kit teaches Claude to get a verdict it can trust. Every claim in the skills is reproduced on a small demo project
by [`tests/measure_traps.sh`](tests/measure_traps.sh). If a claim does not reproduce, it is not in the kit.

## What's inside

| Skill | What it gives Claude |
|---|---|
| **`godot-run`** | A runner (`godot_run.sh`). It finds the engine and isolates the run from your editor settings and `user://` data. It imports when needed, always has a `--quit-after` and wall-clock backstop, and judges the log: `PASS` / `FAIL (reasons)` / `UNVERIFIED` / `NO-ENGINE`. It also covers the Windows PowerShell pitfalls (a GUI build that returns instantly, UTF-16 logs). |
| **`godot-headless-harness`** | A **parse gate** scene that checks every GDScript compiles, with autoloads live. A **diag harness** template that drives your real scenes and autoloads, with coverage counting, so an un-awaited check cannot pass silently. A scaffold script, and the rule that every new check must be seen failing before it counts. |
| **`godot-ci`** | One command for the whole project: import, the parse gate, then every `diag_*` harness, with one verdict. `install` writes a GitHub Actions workflow that runs the same script on Linux. |

The skills trigger on their own. Ask Claude to "check that everything still compiles", "verify the damage fix" or
"set up CI for this Godot project", and it picks the right one.

## Install

In Claude Code:

```
/plugin marketplace add hibi/godot-claude-kit
/plugin install godot-kit@godot-claude-kit
```

The skills are then available as `/godot-kit:godot-run`, `/godot-kit:godot-headless-harness` and
`/godot-kit:godot-ci`. Claude also loads them by itself when a task needs them.

**Requirements:**

- Godot 4.x. The kit was measured on 4.7.2.
- `bash`. On Windows that is Git Bash, which Claude Code already uses.
- The engine binary as `GODOT_BIN`, or `godot` on `PATH`. On Windows, use the `*_console.exe` build.

## Quick start

Tell Claude:

> Add a parse gate and a health harness to this project, run them, and set up CI.

Claude will then:

1. Scaffold `res://tools/ci/parse_gate.tscn` and `res://tools/diag_<name>.tscn`.
2. Write real checks against your code.
3. Break the code on purpose to prove each check fails, then restore it.
4. Run everything through the runner.
5. Write `.github/workflows/godot-ci.yml`.

Or by hand, without Claude, from your project directory. This route needs a clone of this repository:

```bash
KIT=~/godot-claude-kit    # where you cloned it
bash "$KIT/skills/godot-headless-harness/scaffold.sh" --path . gate
bash "$KIT/skills/godot-run/godot_run.sh" --path . --banner '^PARSE-GATE: PASS' res://tools/ci/parse_gate.tscn
bash "$KIT/skills/godot-ci/ci.sh" --path .
```

## Works with MCP servers

Godot MCP servers let an agent launch the editor, edit scenes or read the console. This kit does not replace them.
It answers a different question: *did that run really prove what the agent claims?* Use both.

## Verified on

| Platform | Engine | What ran |
|---|---|---|
| Windows 10, Git Bash and PowerShell 5.1 | 4.7.2 stable | `measure_traps.sh` (every trap above), runner, gate, harness, `ci.sh` incl. each sabotage case |
| Linux (Debian, WSL2) | 4.7.2 stable, official Linux build | `measure_traps.sh`, and the generated workflow's steps executed verbatim (download, import, gate, harness): PASS clean, FAIL with a syntax error |

The workflow has not yet run on GitHub's own runner.

The skills were also tested by a fresh Claude Code session with only the plugin loaded and a plain prompt. The skills
triggered by themselves, and the verdicts matched the ground truth (PASS on the clean demo, FAIL naming the broken
file).

## Repository layout

```
.claude-plugin/        plugin + marketplace manifests
skills/godot-run/      runner + skill
skills/godot-headless-harness/   parse gate + harness templates, scaffold script
skills/godot-ci/       ci.sh, GitHub Actions template
demo/                  small Godot 4 project every claim is measured on
tests/measure_traps.sh reproduces every trap; tests/sabotage/ holds the broken-on-purpose fixtures
```

## Roadmap

- **Multiplayer harness:** headless server and client as two processes, both judged, plus an RPC contract check.
- Screenshot and visual checks.
- A test runner for GUT / gdUnit4.
- A GDScript reviewer agent.

## License

[MIT](LICENSE)
