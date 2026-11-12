#!/usr/bin/env python3
"""Cuts the illustration sheets in design/illustrations into single transparent drawings for the asset catalog.

Run from the repository root: python3 -I tools/slice_illustrations.py
White becomes transparent (colour to alpha), so the ink and the blue keep their strength on paper.
"""
import json
import pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design" / "illustrations"
ASSETS = ROOT / "Kairos" / "Assets.xcassets"
SHEETS = {
    "sheet-life-events.png": (2, 2, ["firstHome", "firstSalary", "business", "inheritance"]),
    "sheet-categories.png": (3, 1, ["spending", "saving", "investing"]),
    "sheet-explainers.png": (3, 2, ["payLater", "budget", "subscriptions", "safetyNet", "compound", "funds"]),
    "sheet-explainers-more.png": (3, 1, ["spread", "calm", "protect"]),
}


def to_alpha(image):
    image = image.convert("RGB")
    out = Image.new("RGBA", image.size)
    source, target = image.load(), out.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b = source[x, y]
            alpha = 255 - min(r, g, b)
            if alpha < 10:
                target[x, y] = (255, 255, 255, 0)
                continue
            share = alpha / 255
            target[x, y] = tuple(max(0, min(255, round((c - (1 - share) * 255) / share))) for c in (r, g, b)) + (alpha,)
    return out


for sheet, (columns, rows, names) in SHEETS.items():
    image = Image.open(SOURCE / sheet).convert("RGB")
    width, height = image.width // columns, image.height // rows
    for index, name in enumerate(names):
        cell = image.crop(((index % columns) * width, (index // columns) * height, (index % columns + 1) * width, (index // columns + 1) * height))
        mask = cell.convert("L").point(lambda value: 255 if value < 236 else 0)
        box = mask.getbbox()
        pad = 8
        box = (max(box[0] - pad, 0), max(box[1] - pad, 0), min(box[2] + pad, cell.width), min(box[3] + pad, cell.height))
        drawing = to_alpha(cell.crop(box))
        folder = ASSETS / f"illustration-{name}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        drawing.save(folder / f"illustration-{name}.png")
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"illustration-{name}.png", "idiom": "universal", "scale": "3x"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n")
        print(name, drawing.size)
