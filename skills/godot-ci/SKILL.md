---
name: godot-ci
description: One trustworthy verdict for a whole Godot 4 project - import, the parse gate, the static RPC check, every harness (single-process and multiplayer) and the GUT/gdUnit4 unit tests in one command - and a GitHub Actions workflow that runs the same thing. Use before a commit or push, when asked to "run all checks", "run CI", "is the project green", or to set up CI / GitHub Actions for a Godot project. Runs through the godot-run skill's runner; the checks themselves come from the godot-headless-harness, godot-multiplayer-harness and godot-unit-tests skills.
---

# godot-ci

`ci.sh` runs everything the project has, and judges each run with the `godot-run` runner (banner + error tokens +
exit code, never the exit code alone):

1. The **parse gate** `res://tools/ci/parse_gate.tscn`. When the project has no gate scene, the kit's script gate
   `parse_gate_script.gd` runs instead (same walk and checks, run as `--script`, no file added to the project); the
   PASS line then says `parse gate (kit script gate)`. The first engine run also does the `--import`.
2. The **static RPC check**: every RPC the project sends must name an `@rpc` function. A call that breaks this
   compiles, so the gate cannot see it (skill `godot-multiplayer-harness`).
3. Every **diag harness** `diag_<name>.tscn`, one process each. It must print `DIAG-<NAME>: PASS`.
4. Every **multiplayer harness** `netdiag_<name>.tscn`, run through `net_run.sh`: a server and a client, each judged.
   Both must print `NETDIAG-<NAME>-SERVER|CLIENT: PASS`.

5. The **unit tests** (GUT or gdUnit4), through `test_run.sh` (skill `godot-unit-tests`). They run when a framework is
   installed under `addons/` and the test directory is known: `--test-dir res://...`, or `"dirs"` in GUT's
   `.gutconfig.json`. A framework without a known directory shows a visible `SKIP` row, and the PASS line says
   `unit tests SKIPPED`.
6. The **golden screenshots**, when you pass `--shot-dir res://tests/shots`: every `<name>.png` with a `<name>.json`
   next to it is shot again through `shot.sh` and compared (skill `godot-screenshot`). Shots need a display. Without
   one (Linux with no `xvfb-run`) there is a visible `SKIP` row and the PASS line says `shots SKIPPED (no display)`.
   A golden made by another driver or GPU is not compared; the row says so, but the frame checks still run.

Harness discovery skips `.godot/`, `addons/` and directories with a `.gdignore`. Every run after the first reuses its
import.

```bash
bash "${CLAUDE_SKILL_DIR}/ci.sh" --path .
bash "${CLAUDE_SKILL_DIR}/ci.sh" --path . --min-harnesses 3    # fail if a harness went missing
```

| Last line | Exit | Meaning |
|---|---|---|
| `GODOT-CI: PASS (parse gate, rpc check, n/n harnesses: d diag, m net)` | 0 | everything passed |
| `GODOT-CI: FAIL (k of n runs failed: <what>)` | 1 | each failed run is named; its output is printed above the summary |
| `GODOT-CI: FAIL (found n harness(es), --min-harnesses m)` | 1 | fewer harnesses than you said exist |
| `GODOT-CI: NO-ENGINE` | 3 | no binary: set `GODOT_BIN` (see the `godot-run` skill) |

If the multiplayer skill's scripts are missing, the PASS line says `rpc check SKIPPED`, and every `netdiag_*` harness
FAILs.

Other options:

- `--gate <res path>`: a gate scene somewhere else. If the scene you name does not exist, that is a FAIL (no fallback
  to the script gate: a typo must not quietly swap the check).
- `--frames N` / `--timeout S`: passed through to every run.
- `--out <dir>`: where the per-run logs go. A fresh temp dir by default; the path is printed either way.
- `--test-dir res://...` (repeatable), `--test-framework gut|gdunit` (when both are installed) and `--min-tests N`
  (default 1) go to the unit-test run.
- `--shot-dir res://...`: the directory of golden screenshots, written by `shot.sh --update-golden`.
- `--require-shots`: every golden must really be compared. No display, or a golden from another renderer (for example
  after a CI image update changed the Mesa version), is then a FAIL instead of a SKIP or a "not compared" note.
- `--candidates <dir>`: for every golden that failed or was not compared, shoot a fresh golden (`<name>.png` +
  `<name>.json`) into that directory. On a CI runner this gives you the golden for the runner's renderer. After a real
  regression it shows the broken frame, so open it before you copy it over the old golden.
- `--no-rpc-check`: skips the static RPC check. Use it only for a project the check misreads (it matches by name),
  and say so when you report. The multiplayer harnesses still run.

## Rules

- **A gate always runs.** `--import` exits 0 on a hard syntax error, so nothing else in the pipeline can tell a broken
  script from a good one. A project without a gate scene gets the kit's script gate. A gate scene of your own
  (skill `godot-headless-harness`) lets you set `MIN_SCRIPTS` and the skipped directories in the project itself.
- **Set `--min-harnesses` to the number of harnesses you have** (diag and netdiag together). Discovery goes by file
  name. A harness that was renamed, moved under `addons/` or into a `.gdignore` directory simply stops being found.
  Without the floor, the run quietly shrinks to the gate and still says PASS.
- **Harnesses follow the templates' naming.** A diag harness is `diag_<name>.tscn` with banner `DIAG-<NAME>: PASS`.
  A multiplayer one is `netdiag_<name>.tscn` with `NETDIAG-<NAME>-SERVER|CLIENT: PASS`. The scaffold scripts of the
  two harness skills write exactly that. Another banner fails here with "banner missing".
- **Read the failed run's output, not just the summary.** Each run's runner lines (matched errors, `FAIL` lines, log
  path) are printed above the summary.

## GitHub Actions

```bash
bash "${CLAUDE_SKILL_DIR}/ci.sh" --path . install                 # Godot version read from GODOT_BIN
bash "${CLAUDE_SKILL_DIR}/ci.sh" --path game install --godot-version 4.7.2-stable
bash "${CLAUDE_SKILL_DIR}/ci.sh" --path . install --shot-dir res://tests/shots   # also the golden screenshots
```

`install` never overwrites a file. It writes:

- Copies of the scripts in `res://tools/ci/`: `ci.sh`, `godot_run.sh`, `net_run.sh`, `rpc_check.sh`, `test_run.sh`,
  `shot.sh`, `shot_capture.gd` and `parse_gate_script.gd`. CI then does not need the plugin. `--dir` puts them
  elsewhere.
- `.github/workflows/godot-ci.yml` at the **git repository root**. It works when the Godot project sits in a
  subdirectory of the repository.

The workflow runs on `ubuntu-latest`:

1. It downloads the official Linux build of that Godot version from the godotengine GitHub releases.
2. With `--shot-dir`: it installs a virtual display (xvfb + Mesa).
3. It runs the same `ci.sh` you run locally. With `--shot-dir` that adds `--shot-dir <dir> --require-shots
   --candidates <logs>/candidates`.
4. It uploads the logs as an artifact, also when the run failed.

**Screenshots on the runner.** A golden made on your machine comes from another renderer than the runner's (Mesa
llvmpipe, OpenGL), so it cannot be compared there. With `--require-shots` the first run goes red, on purpose. Then:

1. Download the `godot-ci-logs` artifact from the run's page and unzip it into a fresh directory.
2. Open every `candidates/<name>.png` and check that it shows the right frame.
3. Copy `<name>.png` and `<name>.json` over your golden directory and commit them.

From then on, the shots are compared. When a runner image update changes the Mesa version, the job goes red again and
leaves new candidates. A plain "not compared" note would let the check go quiet.

After `install`:

1. Run the vendored copy once locally, exactly as the workflow will: `bash <project>/tools/ci/ci.sh --path <project>`.
2. Commit all of the files.
3. To update the copies later, delete them and run `install` again.

## Reporting

Report:

- the `GODOT-CI:` line;
- the summary rows;
- for every FAIL, the runner's matched lines and the log path.

Never report "CI passes" from a run that printed a FAIL row, from a run that used a lower `--min-harnesses` than the
project has, or from a workflow you only wrote but did not see run.
