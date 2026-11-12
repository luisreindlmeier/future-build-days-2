#!/usr/bin/env python3
"""Puts the terminal's real screens into the photographs of the branch.

The scenes in media/source/scenes were generated with a plain green screen on the terminal (and on the phone). This
finds the green, fits the matching screenshot of the app into it in perspective, and keeps whatever is in front of the
screen, a finger for example. Run from the repository root, after `capture.py pad`:  python3 -I media/source/terminal.py
"""
import pathlib
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCENES = ROOT / "media" / "source" / "scenes"
RAW = ROOT / "ios" / ".build" / "media"
OUT = ROOT / "media" / "terminal"

# scene: (screenshot, what the picture shows)
STORY = {
    "01-arrive": ("terminal-start", "She walks in and the terminal asks how her money is doing."),
    "02-agree": ("terminal-consent", "She sees what the check reads, and agrees."),
    "03-check": ("terminal-scan", "The check runs: accounts, peers, well-being, simulation."),
    "04-result": ("terminal-result", "Her tree and her rings. No amounts on the shared screen."),
    "05-code": ("terminal-handoff", "She scans the code to take the check-up with her."),
    "06-phone": ("home", "The figures and the plan open on her own phone."),
    "07-advisor": ("terminal-advisor", "An advisor comes over, already briefed by the summary."),
}


def green(scene):
    """Where the scene is screen green: 255 there, 0 elsewhere."""
    red, grn, blue = scene.split()
    lead = ImageChops.subtract(grn, ImageChops.lighter(red, blue))
    mask = lead.point(lambda value: 255 if value > 70 else 0)
    bright = grn.point(lambda value: 255 if value > 130 else 0)
    mask = ImageChops.multiply(mask, bright)
    return mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))


def corners(mask):
    """The four corners of the green: top left, top right, bottom right, bottom left."""
    pixels = mask.load()
    best = {"tl": None, "tr": None, "br": None, "bl": None}
    score = {"tl": 10 ** 9, "tr": -10 ** 9, "br": -10 ** 9, "bl": 10 ** 9}
    for y in range(mask.height):
        for x in range(mask.width):
            if not pixels[x, y]:
                continue
            total, across = x + y, x - y
            if total < score["tl"]:
                score["tl"], best["tl"] = total, (x, y)
            if total > score["br"]:
                score["br"], best["br"] = total, (x, y)
            if across > score["tr"]:
                score["tr"], best["tr"] = across, (x, y)
            if across < score["bl"]:
                score["bl"], best["bl"] = across, (x, y)
    middle = (sum(p[0] for p in best.values()) / 4, sum(p[1] for p in best.values()) / 4)
    grown = []
    for key in ("tl", "tr", "br", "bl"):
        x, y = best[key]
        grown.append((x + (3 if x > middle[0] else -3), y + (3 if y > middle[1] else -3)))
    return grown


def solve(matrix, vector):
    """Gaussian elimination, enough for the eight unknowns of a perspective fit."""
    size = len(vector)
    rows = [row[:] + [vector[index]] for index, row in enumerate(matrix)]
    for column in range(size):
        pivot = max(range(column, size), key=lambda row: abs(rows[row][column]))
        rows[column], rows[pivot] = rows[pivot], rows[column]
        for row in range(size):
            if row != column:
                factor = rows[row][column] / rows[column][column]
                rows[row] = [a - factor * b for a, b in zip(rows[row], rows[column])]
    return [rows[index][size] / rows[index][index] for index in range(size)]


def perspective(quad, size):
    """Coefficients that take a point of the scene to the point of the screenshot shown there."""
    width, height = size
    source = [(0, 0), (width, 0), (width, height), (0, height)]
    matrix, vector = [], []
    for (x, y), (u, v) in zip(quad, source):
        matrix.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        vector.append(u)
        matrix.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        vector.append(v)
    return solve(matrix, vector)


def compose(name, shot):
    scene = Image.open(SCENES / f"{name}.png").convert("RGB")
    screen = Image.open(RAW / f"{shot}.png").convert("RGB")
    if shot.startswith("terminal"):
        # A terminal has no tablet status bar and no window handle.
        screen = screen.crop((0, 56, screen.width, screen.height - 44))
    mask = green(scene)
    quad = corners(mask)
    fitted = screen.transform(scene.size, Image.Transform.PERSPECTIVE, perspective(quad, screen.size), Image.Resampling.BICUBIC)
    # A screen in a room is a little less white than a screenshot, and glass catches some light.
    fitted = Image.blend(fitted, Image.new("RGB", scene.size, (214, 222, 240)), 0.06)
    shine = Image.new("L", scene.size, 0)
    ImageDraw.Draw(shine).polygon([quad[0], quad[1], (quad[1][0], quad[1][1] + (quad[2][1] - quad[1][1]) * 0.35)], fill=26)
    fitted = Image.composite(Image.new("RGB", scene.size, (255, 255, 255)), fitted, shine.filter(ImageFilter.GaussianBlur(18)))
    # Everything that was green, with the edge of the quad, becomes screen; the rest of the scene stays.
    area = Image.new("L", scene.size, 0)
    ImageDraw.Draw(area).polygon(quad, fill=255)
    inside = ImageChops.multiply(area, mask.filter(ImageFilter.MaxFilter(5)))
    out = Image.composite(fitted, scene, inside.filter(ImageFilter.GaussianBlur(0.8)))
    # Take the green cast off whatever touches the screen: fingers, the frame.
    band = ImageChops.subtract(inside.filter(ImageFilter.MaxFilter(13)), inside)
    red, grn, blue = out.split()
    calm = ImageChops.darker(grn, ImageChops.add(ImageChops.lighter(red, blue), Image.new("L", scene.size, 8)))
    out = Image.merge("RGB", (red, Image.composite(calm, grn, band), blue))
    OUT.mkdir(parents=True, exist_ok=True)
    out.save(OUT / f"{name}.jpg", quality=93, subsampling=0)
    print(name, quad)


if __name__ == "__main__":
    for name, (shot, _) in STORY.items():
        compose(name, shot)
