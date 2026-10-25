---
name: godot-unit-tests
description: Run a Godot 4 project's GUT or gdUnit4 unit tests headless and get a verdict you can trust - from the framework's exit code, its JUnit XML and the traps where both frameworks exit 0 without testing anything. Use when the project has addons/gut or addons/gdUnit4, when asked to run, add or fix unit tests, before reporting that tests pass, or when a test run "passed" suspiciously fast. Runs through the godot-run skill's runner.
---

# godot-unit-tests

Both popular Godot test frameworks can exit **0** without having tested anything. Measured with GUT 9.7.1 and gdUnit4
6.2.2 on Godot 4.7.2 (Windows and Linux) by the kit's `tests/measure_traps.sh`:

| What happened | Exit | What the log says |
|---|---|---|
| GUT: a test file does not parse | **0** | `SCRIPT ERROR: Parse Error`, then `All tests passed!` (that file's tests silently gone) |
| GUT: a test file does not extend `GutTest` | **0** | `Ignoring script ... does not extend GutTest`, then `All tests passed!` |
| GUT: the test directory does not exist, is empty, or its files lack the `test_` prefix | **0** | `[GUT ERROR]: Nothing was run.` |
| GUT: a fresh clone run before `--import` | **0** | `ERROR: Some GUT class_names have not been imported`, no test ran |
| gdUnit4: the test directory does not exist or is empty | **0** | `No test cases found, abort test run!` |
| gdUnit4 started with `-d` and a test file that does not parse (Windows) | — | **hangs forever** at a `debug>` prompt |
| the same on Linux | **0** | `Abnormal exit with 105`, yet the process exits 0 |
| gdUnit4 headless without `--ignoreHeadlessMode` | 103 | `Headless mode is not supported!` |

Where the frameworks do report a failure, the exit code is right:
- GUT exits 1 on a failing assert or a runtime error in a test.
- gdUnit4 exits 100 for those, and 105 for a test file that does not parse.

**A passing test that expects an error still logs `ERROR: ...`** (`assert_push_error` in GUT,
`assert_error(...).is_push_error(...)` in gdUnit4). So "any ERROR line = fail" is wrong for test runs.

## 1. Run the tests

```bash
bash "${CLAUDE_SKILL_DIR}/test_run.sh" --path . --dir res://tests          # framework found under addons/
bash "${CLAUDE_SKILL_DIR}/test_run.sh" --path . --framework gdunit --dir res://test/unit --dir res://test/integration
```

`test_run.sh` does the following:

1. It imports once.
2. It runs the framework's CLI through the `godot-run` runner, which gives isolation and the `--quit-after` and
   wall-clock backstops.
3. It always passes the flags that avoid the traps above:
   - GUT: `-gexit -gdisable_colors -gjunit_xml_file=<out>`.
   - gdUnit4: `--ignoreHeadlessMode -c -rd <out>`, and never `-d`.
4. It judges the run by:
   - the framework's exit code;
   - the **JUnit XML**, written to a fresh directory every run. A missing XML is a FAIL;
   - the trap lines: `Parse Error`, `Ignoring script`, `[GUT ERROR]`, `class_names have not been imported`,
     `No test cases found`.

| Last line | Exit | Meaning |
|---|---|---|
| `GODOT-TEST: PASS (gut: n passed, 0 failed, p pending/skipped, r risky (of t))` | 0 | at least `--min-tests` (default 1) tests passed, none failed |
| `GODOT-TEST: FAIL (<reasons> \| <counts>)` | 1 | every reason listed: failing tests, a file that does not compile, an ignored test file, nothing run, missing XML, timeout |
| `GODOT-TEST: NO-ENGINE` | 3 | no binary: see the `godot-run` skill |

Options:

- `--dir res://...` is required. It is repeatable and must exist; a missing directory is a FAIL, not "0 tests".
  GUT falls back to `"dirs"` in `res://.gutconfig.json`. gdUnit4 has no project-wide default.
- `--framework gut|gdunit` is needed only when both are installed.
- `--min-tests N` (default 1) counts tests that **passed**. Set it near the number you have, so a test file that
  silently drops out shows up.
- `--strict` also fails on pending, skipped and risky (no assert) tests, and on gdUnit4's exit **101**. 101 is
  "warnings": measured on a test that leaks a node (an orphan). Without `--strict` it passes with a note.
- `--out <dir>` keeps the log and XML. Never point it inside the project: gdUnit4's default writes
  `reports/report_N` into the project on every run.

The `godot-ci` skill runs this too, when a framework is installed and it knows the test directory (`--test-dir`).

## 2. Writing tests that prove something

The rules of the `godot-headless-harness` skill apply here as well:

- **Test the real code.** Use the real classes and scenes: `add_child_autofree(Health.new())` in GUT,
  `auto_free(...)` plus `add_child` in gdUnit4, so that `_ready` runs. Never test a copy of the logic.
- **Assert the value.** For example `assert_eq(h.hp, 0)`, not `assert_true(h.hp != 100)`.
- **Every test asserts.** GUT marks a test without an assert as *risky*. `test_run.sh` does not count it as passed.
- **UI and input tests do not work headless in gdUnit4.** Its own warning says so: input events are not delivered in
  headless mode. Keep those out of the headless run.

## 3. Prove the tests bite

A test is not done until you have seen it fail for the right reason. Measured on the demo with both frameworks:

1. Remove the clamp in `Health.damage`. Expect exactly that test to fail, with the wrong value (`-50`
   instead of `0`), and `GODOT-TEST: FAIL`.
2. Restore the file byte for byte (`cmp`). Expect `GODOT-TEST: PASS`.

If the run stayed green while the code was broken, the test is worthless.

## 4. Reporting

Report:

- the `GODOT-TEST:` line with its counts;
- the failing test names and messages from the log;
- the log and XML paths.

Never write "tests pass" when you see any of these:

- a FAIL;
- `0 passed`;
- `--min-tests` set below the real number of tests;
- a run whose summary you did not see.
