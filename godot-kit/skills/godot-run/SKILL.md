---
name: godot-run
description: Run a Godot 4 project or scene headless and judge whether it REALLY worked. Use whenever you need to run, import, smoke-test or launch a Godot project, execute a harness/test/gate scene, or verify a GDScript change by running it - before trusting any exit code. Covers finding the engine binary, isolating the run from the user's editor settings, --import, --quit-after, reading the log, and the Windows PowerShell pitfalls.
---

# godot-run

**A Godot exit code of 0 proves nothing.** All of these exit 0 (Godot 4.7.2, and the same on 4.4.1, 4.5.2 and 4.6.3
unless noted; reproduced by the kit's `tests/measure_traps.sh`):

| What happened | Exit | Log |
|---|---|---|
| `--import` on a project with a hard syntax error | 0 | nothing at all (4.4.1: the `SCRIPT ERROR`, still exit 0) |
| scene whose own script does not parse | 0 | `SCRIPT ERROR`, then the scene runs as a bare node |
| harness that forgot to `await` an async check | 0 | `PASS` banner, and a `FAIL` line *after* it |
| scene run with `--user-data-dir` (a flag Godot 4 does not have) | 0 | empty: the scene never ran |
| fresh clone run before `--import` | 0 | false `Parse Error: Could not find type "<ClassName>"` |
| a healthy scene that simply prints nothing | 0 | byte-identical to the "never ran" log above |

So a run passes only when it can show positive proof that it ran: exit 0, **and** no error tokens in the log, **and**
the banner the scene prints after its last step.

## 1. Find the engine

Use the first one that works, in order. Never guess or hard-code an install path.

1. `$GODOT_BIN` if it is set.
2. `godot` on `PATH`.
3. Otherwise **ask the user** for the path, and suggest they set `GODOT_BIN`.

On Windows, `GODOT_BIN` should point at the `*_console.exe` build (see section 4). Check it with `"$GODOT_BIN" --version`.

## 2. Run it with the runner (default)

```bash
bash "${CLAUDE_SKILL_DIR}/godot_run.sh" --path <project dir> --banner '<regex of the final line>' res://path/scene.tscn
```

Examples:

```bash
bash "${CLAUDE_SKILL_DIR}/godot_run.sh" --path . --banner '^PARSE-GATE: PASS' res://tools/ci/parse_gate.tscn
bash "${CLAUDE_SKILL_DIR}/godot_run.sh" --path . --banner '^DIAG-HEALTH: PASS' --no-import res://tools/diag_health.tscn
bash "${CLAUDE_SKILL_DIR}/godot_run.sh" --path . --frames 300 res://src/main.tscn    # smoke run, no banner
```

The runner handles every step for you:

1. **Isolation.** It points APPDATA/LOCALAPPDATA/HOME/XDG_* at a throwaway directory for every engine process, the
   import included. The user's editor settings, project list and `user://` data are never read or written.
2. **Import.** It runs `--import` first, unless you pass `--no-import`.
3. **The run.** The scene runs with `--headless --quit-after <frames>`. There is also a wall-clock `timeout` when
   `timeout` exists on the machine.
4. **The verdict.** It strips CR, greps the log for tokens, and prints a verdict on its last line, with a matching
   exit code:

| Last line | Exit | Meaning |
|---|---|---|
| `GODOT-RUN: PASS` | 0 | banner found, engine exit 0, no `SCRIPT ERROR` / `Parse Error` / `Compile Error` / `ERROR:` / `FAIL` line |
| `GODOT-RUN: FAIL (<reasons>)` | 1 | each reason listed: engine exit, script error, ERROR line, FAIL line, banner missing, timeout |
| `GODOT-RUN: UNVERIFIED (...)` | 2 | no `--banner` given and nothing went wrong. That also proves nothing ran |
| `GODOT-RUN: NO-ENGINE` | 3 | no binary: ask the user, set `GODOT_BIN` |
| `GODOT-RUN: IMPORTED` | 0 | `--import-only`: the isolated import exited 0. That says nothing about the scripts. |

**Several engine processes on one project** (a server and its clients): import once with `--import-only`, then start
each process with `--no-import`. Parallel imports would write the same `.godot/` cache at the same time. The
`godot-multiplayer-harness` skill's `net_run.sh` does exactly this.

**Keeping what the run wrote to `user://`:** `--home <dir>` uses that directory as the isolated APPDATA/HOME and does not
delete it afterwards. Without it, the isolation directory is thrown away after the run. `godot-unit-tests` uses it to
collect gdUnit4's reports.

**Anything that must draw** (screenshots): `--windowed` drops `--headless` from the scene run; the import stays
headless. `--headless` never draws a frame. A windowed run needs a display; on Linux, run it under `xvfb-run`. The
`godot-screenshot` skill's `shot.sh` does all of this.

The runner prints the log path. Read the log whenever the verdict is not PASS. Pass `--allow-engine-errors` only when
the project has known, unrelated `ERROR:` noise, and say so when you report.

When you want a PASS, give the run a banner. If the scene has none, write a harness (skill `godot-headless-harness`).
Do not call an UNVERIFIED run "working".

## 3. Rules when you run the engine by hand

- **Isolate every engine process**, `--import` too:
  - Windows: `APPDATA` and `LOCALAPPDATA`.
  - Linux: `HOME` and `XDG_*`.

  There is no `--user-data-dir` flag in Godot 4. The engine ignores it, and a scene run with it exits 0 with empty
  output.
- **Run `--import` first** whenever any of these is true:
  - it is a fresh clone (no `.godot/`);
  - a `class_name` was added or renamed;
  - files were moved.

  Without it, correct scripts report `Could not find type` and the run still exits 0.
- **`--import` is not a parse check.** A syntax error passes it with exit 0 and no output. To check that every script
  compiles, use the parse gate scene (skill `godot-headless-harness`).
- **Do not use `--check-only --script` as a gate.** It does catch syntax errors. But it also reports a false
  `Identifier not found: <Autoload>` on every correct script that names an autoload, because a `--script` run never
  instantiates autoloads.
- **Always pass `--quit-after N`.** A run whose scene never loads does not exit by itself.
  - N counts **frames**, not seconds. On the measuring machine, 60 frames took ~0.85 s and 600 frames ~4.5 s.
  - A run that never loads burns the whole count before it exits.
- **Capture the output.** Send stdout and stderr to a file (`> run.log 2>&1`), strip `\r`, and grep for tokens:
  - errors: `SCRIPT ERROR|Parse Error|Compile Error|^ERROR:|^\s*FAIL\b`
  - success: your banner

  Judge from the matched lines, never from a feeling about the prose.
- **Strip `\r` before matching.** The engine writes CRLF on Windows, even into a Git Bash pipe. A banner regex anchored
  with `$` never matches the raw log.

## 4. Windows: Git Bash vs PowerShell

- **Git Bash:** the runner works as is. Both the GUI and the `*_console.exe` build return their output and exit code here.
- **PowerShell, the GUI build (`Godot_*.exe` without `_console`):**
  - `& $godot ...` returns after ~0.2 s with an empty `$LASTEXITCODE` and an empty log.
  - The engine keeps running in the background.
  - Use the `*_console.exe` build, or `Start-Process -Wait` (below).
- **Windows PowerShell 5.1, `*>` / `2>&1` on the engine:**
  - The first stderr line gets turned into a `NativeCommandError` record: `<exe> : SCRIPT ERROR: ...`, hard-wrapped at
    console width, followed by a `CategoryInfo` block.
  - A pattern anchored at the line start misses that first error, and a token can be split across two lines.
  - The file is written as **UTF-16LE**. `grep` from Git Bash finds nothing in it, so a log full of errors reads as
    "no errors found".
  - Redirect with `Start-Process` into separate files instead.
- **`$env:` changes last for the rest of the PowerShell session.** Save the values and restore them, as below.

```powershell
$godot = $env:GODOT_BIN    # the *_console.exe build
$proj  = "."               # Start-Process does not quote arguments: wrap a path with spaces as '"C:\my proj"'
$work  = Join-Path $env:TEMP ("godot_run_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force (Join-Path $work "home") | Out-Null
$saved = $env:APPDATA, $env:LOCALAPPDATA, $env:HOME
try {
    $env:APPDATA = $env:LOCALAPPDATA = $env:HOME = Join-Path $work "home"
    $run = @{ FilePath = $godot; NoNewWindow = $true; Wait = $true; PassThru = $true }
    $null = Start-Process @run -ArgumentList "--headless", "--path", $proj, "--import" `
        -RedirectStandardOutput "$work\import.out" -RedirectStandardError "$work\import.err"
    $p = Start-Process @run -ArgumentList "--headless", "--path", $proj, "--quit-after", "3600", "res://tools/diag_health.tscn" `
        -RedirectStandardOutput "$work\run.out" -RedirectStandardError "$work\run.err"
    $code = $p.ExitCode
} finally {
    $env:APPDATA, $env:LOCALAPPDATA, $env:HOME = $saved
}
$log    = Get-Content "$work\run.out", "$work\run.err"
$bad    = $log | Select-String -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|^ERROR:|^\s*FAIL\b'
$banner = $log | Select-String -Pattern '^DIAG-HEALTH: PASS' -Quiet
"exit=$code errors=$(@($bad).Count) banner=$banner verdict=$(if ($code -eq 0 -and -not $bad -and $banner) {'PASS'} else {'FAIL'})"
$bad | ForEach-Object { "  | $($_.Line)" }
```

With separate files, stdout and stderr are no longer interleaved, so an error line cannot be placed relative to a
`print`. When the order matters, run the bash runner instead.

## 5. Report what you saw

When you report a run, include:

- the verdict line;
- the matched error and banner lines;
- the log path.

Never write "it runs" or "tests pass" on an UNVERIFIED or FAIL verdict. If you used `--no-import` or
`--allow-engine-errors`, say so.
