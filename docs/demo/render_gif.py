"""Render a terminal-style replay GIF from a JSON scene list.

Usage: python render_gif.py scenes.json out.gif   (needs Pillow; fonts are the Windows Cascadia Mono)
       python docs/demo/render_gif.py docs/demo/scenes.json docs/demo.gif

scenes.json: {"title": str, "prompt": str, "events": [{"text": str, "style": str, "delay": ms}, ...], "hold": ms}
Every text line comes verbatim from a recorded session; this script only lays it out and colours it.
"""
import json
import sys
import textwrap

from PIL import Image, ImageDraw, ImageFont

W, H = 1040, 600
PAD_X, TOP = 22, 52
FONT_SIZE, LINE_H = 16, 22
COLS = 98
ROWS = (H - TOP - 16) // LINE_H

BG = (24, 26, 31)
BAR = (40, 43, 51)
FG = (214, 218, 224)
DIM = (128, 134, 145)
STYLES = {
    "prompt": (230, 232, 236),
    "user": (230, 232, 236),
    "tool": (125, 185, 255),
    "dim": DIM,
    "ok": (110, 210, 130),
    "fail": (255, 110, 105),
    "verdict_fail": (255, 90, 85),
    "verdict_pass": (90, 220, 120),
    "text": FG,
    "head": (240, 200, 110),
}

font = ImageFont.truetype("C:/Windows/Fonts/CascadiaMono.ttf", FONT_SIZE)
bold = ImageFont.truetype("C:/Windows/Fonts/CascadiaMono.ttf", FONT_SIZE)
bold.set_variation_by_name("Bold")


def wrap(text, style):
    out = []
    for raw in text.split("\n"):
        indent = len(raw) - len(raw.lstrip(" "))
        parts = textwrap.wrap(raw.strip(" "), COLS, initial_indent=" " * indent,
                              subsequent_indent=" " * (indent + 2)) or [""]
        out += [(p, style) for p in parts]
    return out


def frame(title, lines, cursor=False):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 34], fill=BAR)
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse([16 + i * 22, 11, 28 + i * 22, 23], fill=c)
    tw = d.textlength(title, font=font)
    d.text(((W - tw) / 2, 8), title, font=font, fill=DIM)
    visible = lines[-ROWS:]
    y = TOP
    for text, style in visible:
        f = bold if style.startswith("verdict") or style == "head" else font
        x = PAD_X
        if text.startswith("⏺ "):  # the bullet glyph is not in the font: draw it
            d.ellipse([x + 1, y + 6, x + 10, y + 15], fill=STYLES["tool"] if style == "tool" else FG)
            text, x = "  " + text[2:], PAD_X
        d.text((x, y), text, font=f, fill=STYLES.get(style, FG))
        y += LINE_H
    if cursor and visible:
        last, st = visible[-1]
        x = PAD_X + d.textlength(last, font=font)
        d.rectangle([x + 1, y - LINE_H + 3, x + 9, y - 3], fill=STYLES["user"])
    return img


def main():
    spec = json.load(open(sys.argv[1], encoding="utf-8"))
    title = spec["title"]
    frames, durations = [], []

    def add(img, ms):
        frames.append(img)
        durations.append(ms)

    lines = []
    add(frame(title, [("> ", "prompt")], cursor=True), 700)
    prompt = spec["prompt"]
    typed = ""
    step = 6
    for i in range(0, len(prompt), step):
        typed = prompt[: i + step]
        cur = wrap("> " + typed, "user")
        add(frame(title, cur, cursor=True), 45)
    lines = wrap("> " + prompt, "user") + [("", "text")]
    add(frame(title, lines), 900)
    for ev in spec["events"]:
        lines += wrap(ev["text"], ev.get("style", "text"))
        add(frame(title, lines), ev.get("delay", 250))
    durations[-1] = spec.get("hold", 6000)

    pal = [f.convert("P", palette=Image.Palette.ADAPTIVE, colors=32) for f in frames]
    pal[0].save(sys.argv[2], save_all=True, append_images=pal[1:], duration=durations, loop=0, optimize=True,
                disposal=1)
    print(f"{len(frames)} frames, {sum(durations) / 1000:.1f} s")


main()
