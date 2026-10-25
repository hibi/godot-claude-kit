---
name: godot-ci
description: One trustworthy verdict for a whole Godot 4 project - import, the parse gate and every diag harness in one command - and a GitHub Actions workflow that runs the same thing. Use before a commit or push, when asked to "run all checks", "run CI", "is the project green", or to set up CI / GitHub Actions for a Godot project. Runs through the godot-run skill's runner; the checks themselves come from the godot-headless-harness skill.
---

# godot-ci

`ci.sh` runs everything the project has, and judges each run with the `godot-run` runner (banner + error tokens +
exit code, never the exit code alone):

1. the **parse gate** `res://tools/ci/parse_gate.tscn`. The first run also does the `--import`.
2. every **diag harness** `diag_<name>.tscn` in the project, each of which must print `DIAG-<NAME>: PASS`.
   - `.godot/`, `addons/` and directories with a `.gdignore` are skipped.
   - These runs reuse the import from step 1.

```bash
bash "${CLAUDE_SKILL_DIR}/ci.sh" --path .
bash "${CLAUDE_SKILL_DIR}/ci.sh" --path . --min-harnesses 3    # fail if a harness went missing
```

| Last line | Exit | Meaning |
|---|---|---|
| `GODOT-CI: PASS (parse gate + n/n diag harnesses)` | 0 | the gate and every harness passed |
| `GODOT-CI: FAIL (k of n runs failed: <scenes>)` | 1 | each failed run is named; its runner output is printed above the summary |
| `GODOT-CI: FAIL (found n diag harness(es), --min-harnesses m)` | 1 | fewer harnesses than you said exist |
| `GODOT-CI: NO-ENGINE` | 3 | no binary: set `GODOT_BIN` (see the `godot-run` skill) |

Other options:

- `--gate <res path>`: a gate somewhere else.
- `--frames N` / `--timeout S`: passed through to every run.
- `--out <dir>`: where the per-run logs go. A fresh temp dir by default; the path is printed either way.

## Rules

- **The gate is required.** Without it the run is a FAIL, even when every harness passes. `--import` exits 0 on a hard
  syntax error, so nothing else in the pipeline can tell a broken script from a good one. If the project has no gate,
  scaffold one (skill `godot-headless-harness`).
- **Set `--min-harnesses` to the number of harnesses you have.** Discovery goes by file name. A harness that was
  renamed, moved under `addons/` or into a `.gdignore` directory simply stops being found. Without the floor, the run
  quietly shrinks to the gate and still says PASS.
- **Harnesses follow the template's naming.** The scene is `diag_<name>.tscn` and the banner is `DIAG-<NAME>: PASS`
  (what `scaffold.sh harness <name>` writes). A harness that prints another banner fails here with "banner missing".
- **Read the failed run's output, not just the summary.** Each run's runner lines (matched errors, `FAIL` lines, log
  path) are printed above the summary.

## GitHub Actions

```bash
bash "${CLAUDE_SKILL_DIR}/ci.sh" --path . install                 # Godot version read from GODOT_BIN
bash "${CLAUDE_SKILL_DIR}/ci.sh" --path game install --godot-version 4.7.2-stable
```

`install` writes three files and never overwrites one:

- `res://tools/ci/ci.sh` and `res://tools/ci/godot_run.sh`: copies of the scripts, so CI does not need the plugin.
  `--dir` puts them elsewhere.
- `.github/workflows/godot-ci.yml` at the **git repository root**. It works when the Godot project sits in a
  subdirectory of the repository.

The workflow runs on `ubuntu-latest`:

1. It downloads the official Linux build of that Godot version from the godotengine GitHub releases.
2. It runs the same `ci.sh` you run locally.
3. It uploads the logs as an artifact, also when the run failed.

After `install`:

1. Run the vendored copy once locally, exactly as the workflow will: `bash <project>/tools/ci/ci.sh --path <project>`.
2. Commit all three files.
3. To update the copies later, delete them and run `install` again.

## Reporting

Report:

- the `GODOT-CI:` line;
- the summary rows;
- for every FAIL, the runner's matched lines and the log path.

Never report "CI passes" from a run that printed a FAIL row, from a run that used a lower `--min-harnesses` than the
project has, or from a workflow you only wrote but did not see run.
