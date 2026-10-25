---
name: godot-screenshot
description: Render a Godot 4 scene to a PNG in a real (off-screen) window, check the frame is not broken, compare it with a golden image, and then LOOK at it. Use after changing anything visible (UI, HUD, layout, materials, camera, lighting, a scene's node tree), when asked whether something "looks right", for a screenshot or visual-regression check, or before reporting a visual change as done. A headless run cannot do this - it never draws a frame. Runs through the godot-run skill's runner.
---

# godot-screenshot

`--headless` never draws a pixel, and every way of asking it for one still exits **0**. A drawing run has its own
traps: it can produce a perfectly valid PNG of nothing. Measured on Godot 4.7.2 (Windows 10 with an NVIDIA GPU;
Debian under xvfb with Mesa llvmpipe) by the kit's `tests/measure_traps.sh`:

| What happened | Exit | What you get |
|---|---|---|
| `--headless`, capture awaits `RenderingServer.frame_post_draw` | **0** | nothing: the await never returns, the run burns its whole `--quit-after` |
| `--headless`, capture without that await | **0** | `get_image()` returns null, one `ERROR: Parameter "t" is null` |
| `--headless --write-movie` | crash | signal 11 |
| a drawing run, image grabbed before the frame is drawn | **0** | at startup: a 4x4 placeholder (Windows) or null (Linux); once the scene is in: a full-size PNG, every pixel black |
| a 3D scene without a current camera | **0** | a valid PNG, every pixel the clear color |
| the scene's script does not parse | **0** | a plausible PNG (the HUD is there, the spawned enemies are not); only a `SCRIPT ERROR` line tells |
| Linux under xvfb, default Vulkan on llvmpipe | crash | signal 11; `--rendering-driver opengl3` works |
| Linux, no display and no `--headless` | 1 | `Unable to create DisplayServer, all display drivers failed` |
| a drawing run on a machine with ALSA but no sound card (a CI runner) | **0** | one `ERROR: Condition "status < 0" is true. Returning: ERR_CANT_OPEN` from the audio driver: a judge that fails on ERROR lines fails a good frame. `shot.sh` passes `--audio-driver Dummy` |

Rendering facts that the golden comparison relies on:

- The same driver on the same GPU renders **byte-identical** PNGs, run after run.
- Vulkan and OpenGL on the same GPU render different pixels, and so does another GPU.
- `--resolution WxH` is honored by a window parked off-screen (Windows) and under xvfb.

## 1. Take the shot

```bash
bash "${CLAUDE_SKILL_DIR}/shot.sh" --path . --out /tmp/shots/main.png                     # the project's main scene
bash "${CLAUDE_SKILL_DIR}/shot.sh" --path . --scene res://ui/menu.tscn --size 1920x1080 --out /tmp/shots/menu.png
```

What `shot.sh` does:

1. **Import.** It runs the project's import once, headless.
2. **Run.** It runs the capture script from this skill's directory as `--script`. No script or scene is added to the
   project; the import writes its usual `.godot/` cache, as opening the editor would. Autoloads are present. It uses
   the runner's `--windowed` mode, so isolation, the frame backstop and the judging of the log all apply.
3. **Display.**
   - Windows: a normal window, parked off-screen at `--position -10000,-10000`. macOS takes the same path, but it
     has not been measured.
   - Linux: `$DISPLAY` if set; otherwise `xvfb-run` with OpenGL; otherwise `NO-DISPLAY`.
4. **Capture.** The scene runs `--settle` frames (default 10), then waits until the frame is **drawn**, then grabs it.
5. **Judge.** It fails on any of these:
   - the run is headless;
   - the image is null;
   - the size is not `--size`;
   - the frame is uniform;
   - any `SCRIPT ERROR` or `ERROR:` line in the log;
   - a golden mismatch.

| Last line | Exit | Meaning |
|---|---|---|
| `GODOT-SHOT: PASS <png>` | 0 | frame drawn, right size, not blank, clean log; golden matched if one was given |
| `GODOT-SHOT: FAIL (why)` | 1 | the first failure; the PNG is still written when there was an image, so you can look at it, and the run log lands next to it (`<out>.log`) |
| `GODOT-SHOT: UNVERIFIED (...)` | 2 | the frame passed, but the golden came from another driver/GPU/engine and was **not** compared |
| `GODOT-SHOT: NO-ENGINE` | 3 | no binary: see the `godot-run` skill |
| `GODOT-SHOT: NO-DISPLAY` | 4 | Linux without a display or `xvfb-run` (`apt install xvfb`): nothing can be drawn here |

Raise `--settle` for anything that animates in: tweens, intros, a fade. 10 frames is enough for a scene that is
ready in `_ready`.

## 2. Look at it - PASS is not "looks right"

The automated checks catch a **broken** frame: blank, wrong size, engine errors. They cannot tell that a label
overlaps a button, that text is cut off, or that the wrong panel is open. So after every shot:

1. **Open the PNG with the Read tool.** It shows you the image.
2. Before you look, write down what the change should have produced: which element, where, which text, which color.
3. Compare the image against that list. Say what you see in concrete words, for example "score label top-left,
   reads `score: 0`; three red boxes centered; nothing overlaps". Never write just "looks good".
4. If something is off, fix it and shoot again. The PNG is the evidence; the exit code is not.

## 3. Golden images (visual regression)

Write a golden only after you have looked at the shot and it is right:

```bash
bash "${CLAUDE_SKILL_DIR}/shot.sh" --path . --out /tmp/shots/main.png --golden tests/shots/main.png --update-golden
bash "${CLAUDE_SKILL_DIR}/shot.sh" --path . --out /tmp/shots/main.png --golden tests/shots/main.png
```

`--out` must be a different file from `--golden`, and `shot.sh` refuses the same path for both: the frame is
written first, so a shared path would compare the golden with itself.

`--update-golden` writes two files:

- `main.png`, the golden image;
- `main.json`, with the scene, the size, and **who rendered it**: driver, GPU, graphics API version, engine version.

Inside the project it also writes a `.gdignore` next to them, so the editor does not import the goldens as textures.

A later run compares the frame with the golden **only when all of that matches**. If the driver or GPU differs, it
says `UNVERIFIED` and does not compare: the pixels would differ for no reason. Make the goldens on the machine and
driver that will check them.

`--max-rmse` (default 0.5, on a 0-255 scale) is the allowed root-mean-square difference. Measured on the demo at
1280x720:

| Change | rmse |
|---|---|
| the same scene, rendered again | 0.000 |
| one digit of a 32 px label changed (`score: 0` -> `score: 8`) | 1.39 |
| the HUD label moved off-screen | 4.44 |

A smaller change, such as one small icon, can fall below 0.5. The golden does not replace looking.

## 4. Prove it bites

As with every harness, make the check fail once for the right reason:

1. Break something visible, for example move the HUD label off-screen.
2. Expect `FAIL ... differs from golden ... rmse 4.441`.
3. Restore the file byte for byte (`cmp`). Expect `PASS`.

## 5. CI

`ci.sh --shot-dir res://tests/shots` (skill `godot-ci`) re-shoots every `<name>.png` that has a `<name>.json` next
to it, and compares it with the golden.

- With no display, the summary says `SKIP shot ... (no display)`, never PASS.
- A golden made on your GPU is not compared on a CI runner's software renderer (`UNVERIFIED`). The frame checks still
  run there: drawn, right size, not blank, no engine error.
- `--require-shots` turns both of these into a FAIL. Use it when the goldens were made on the CI machine itself, so a
  missing display or a changed renderer cannot quietly switch the compare off.
- Measured on GitHub's `ubuntu-latest` with the kit's own workflow. After
  `apt-get install xvfb libgl1-mesa-dri libxcursor1 libxinerama1 libxrandr2 libxi6 libxkbcommon0 libfontconfig1`,
  the frame rendered with OpenGL on llvmpipe (Mesa 25.2.8).
- That runner has ALSA but no sound card, which is where the audio `ERROR` in the table above was found.
- The kit keeps its golden, rendered on that runner, in `demo/tests/shots/` and runs `ci.sh` with `--require-shots`.
  When the job fails, a final step leaves a fresh candidate golden in the logs artifact.

## 6. Reporting

Report:

- the `GODOT-SHOT:` line;
- the PNG path;
- what you saw in the image, in concrete words;
- the golden's rmse, if one was compared.

Never write "it looks right" when any of these is true:

- you did not open the PNG;
- the verdict was FAIL or NO-DISPLAY;
- the verdict was UNVERIFIED and you skipped looking.
