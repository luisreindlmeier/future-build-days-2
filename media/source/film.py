#!/usr/bin/env python3
"""Cuts the demo film: a title card, one scene per screen with the recording in a phone and a caption beside it,
the terminal in the branch, and a closing card. Run from the repository root, after `capture.py clips`,
`mockups.py` and `terminal.py`:  python3 -I media/source/film.py

Captions and cards are small HTML pages photographed by headless Chrome; ffmpeg lays the recordings into the phone
and joins the scenes with short cross fades. The film has no sound.
"""
import pathlib
import subprocess
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW = ROOT / "ios" / ".build" / "media"
WORK = RAW / "film"
OUT = ROOT / "media" / "demo" / "kairos-demo.mp4"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SIZE = (1920, 1080)
SCREEN = (448, 974)
PLACE = (1262, 53)
FADE = 0.45
LEAD = 2.25

# recording, seconds shown, title, line
SCENES = [
    ("welcome", 4.6, "Meet Kairos", "A check-up for your money, with a coach that explains it in plain words."),
    ("scan", 8.4, "A check-up in seconds", "It reads accounts, cards and portfolio, compares them with households like yours and simulates what comes next."),
    ("home", 5.6, "One score, three rings", "Financial health from 0 to 100, for spending, saving and investing."),
    ("spending", 6.2, "See what is behind it", "Every area against your peers, and a short film where it helps."),
    ("tree", 6.6, "Your wealth tree", "Leaves are spending, the trunk is investing, the roots are savings."),
    ("tree-bough", 5.0, "Tap any part", "A bough turns to you and tells you what it stands for."),
    ("tree-storm", 6.0, "Test it in a storm", "A market drop shows whether your savings hold."),
    ("step", 4.6, "A plan with real steps", "What a step changes, how your bank data checks it, and a film to watch first."),
    ("film", 4.2, "Explained in two minutes", "Paying later, ETFs, the safety net: short films where they matter."),
    ("outlook", 4.4, "See where you are heading", "2,000 simulated futures, with the change and without."),
    ("coach", 5.0, "Ask the coach", "Answers come from checked figures. Product advice stays with your advisor."),
]
# photograph, seconds shown, title, line
BRANCH = [
    ("01-arrive", 3.0, "Start at the branch", "The same check-up at a self-service terminal."),
    ("04-result", 3.0, "Your tree, no amounts", "The shared screen shows the tree and the rings, never a figure."),
    ("05-code", 3.0, "Take it with you", "A code hands the check-up over to your phone."),
    ("06-phone", 3.0, "Continue on your phone", "The figures and the plan open there, for your eyes only."),
]

BACK = "radial-gradient(1300px 900px at 78% 20%, #3d52e0 0%, rgba(61,82,224,0) 62%), radial-gradient(900px 800px at 0% 100%, #2a2f86 0%, rgba(42,47,134,0) 70%), linear-gradient(160deg, #23277a 0%, #16184b 45%, #0c0e30 100%)"
STYLE = """* { margin: 0; box-sizing: border-box; }
html, body { width: 1920px; height: 1080px; overflow: hidden; }
body { font-family: -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif; -webkit-font-smoothing: antialiased; color: #fff; position: relative; }
.name { position: absolute; left: 140px; top: 96px; font-size: 40px; font-weight: 700; letter-spacing: -0.5px; display: flex; align-items: center; gap: 16px; }
.name img { width: 78px; }
h1 { position: absolute; left: 140px; top: 372px; width: 980px; font-size: 100px; line-height: 1.04; font-weight: 800; letter-spacing: -3px; }
p { position: absolute; left: 144px; width: 860px; font-size: 40px; line-height: 1.32; font-weight: 500; color: rgba(255,255,255,.76); }
.dots { position: absolute; left: 144px; top: 944px; display: flex; gap: 12px; }
.dots i { width: 14px; height: 14px; border-radius: 7px; background: rgba(255,255,255,.22); }
.dots i.on { width: 46px; background: #fff; }
"""


def shoot(name, html):
    WORK.mkdir(parents=True, exist_ok=True)
    page = WORK / f"{name}.html"
    page.write_text(f"<!doctype html><meta charset='utf-8'><style>{STYLE}</style>{html}")
    subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1", f"--window-size={SIZE[0]},{SIZE[1]}",
                    "--virtual-time-budget=3000", f"--screenshot={WORK / (name + '.png')}", page.as_uri()], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    return WORK / f"{name}.png"


def caption(index, title, line):
    mascot = (RAW / "mascot-smile.png").as_uri()
    lines = 2 if len(title) > 19 else 1
    dots = "".join(f"<i class='{'on' if dot == index else ''}'></i>" for dot in range(len(SCENES)))
    return f"""<body style="background:{BACK}"><div class="name"><img src="{mascot}">Kairos</div>
<h1>{title}</h1><p style="top:{372 + 104 * lines + 44}px">{line}</p><div class="dots">{dots}</div></body>"""


def card(title, line, note=""):
    mascot = (RAW / "mascot-cheer.png").as_uri()
    return f"""<body style="background:{BACK}">
<img src="{mascot}" style="position:absolute;left:50%;top:150px;width:330px;margin-left:-165px;filter:drop-shadow(0 30px 34px rgba(8,10,50,.4))">
<h1 style="left:0;width:1920px;top:520px;text-align:center;font-size:150px">{title}</h1>
<p style="left:360px;width:1200px;top:720px;text-align:center;font-size:50px">{line}</p>
<p style="left:360px;width:1200px;top:930px;text-align:center;font-size:30px;color:rgba(255,255,255,.5)">{note}</p></body>"""


def branch(photo, title, line):
    picture = (ROOT / "media" / "terminal" / f"{photo}.jpg").as_uri()
    return f"""<body style="background:#0c0e30 url('{picture}') center/cover">
<div style="position:absolute;inset:0;background:linear-gradient(0deg, rgba(12,14,48,.94) 0%, rgba(12,14,48,.7) 20%, rgba(12,14,48,0) 44%)"></div>
<h1 style="top:auto;bottom:150px;width:1500px;font-size:84px">{title}</h1><p style="top:auto;bottom:84px;width:1500px">{line}</p></body>"""


def phone_parts():
    """The rounded mask for the recording and the body of the phone that goes over it."""
    scale = 4
    width, height = SCREEN
    mask = Image.new("L", (width * scale, height * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width * scale - 1, height * scale - 1), radius=61 * scale, fill=255)
    mask.resize(SCREEN, Image.Resampling.LANCZOS).save(WORK / "mask.png")
    edge = 12
    body = Image.new("RGBA", ((width + 2 * edge) * scale, (height + 2 * edge) * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    draw.rounded_rectangle((0, 0, body.width - 1, body.height - 1), radius=73 * scale, fill=(92, 96, 128, 255))
    draw.rounded_rectangle((2 * scale, 2 * scale, body.width - 1 - 2 * scale, body.height - 1 - 2 * scale), radius=71 * scale, fill=(10, 11, 22, 255))
    draw.rounded_rectangle((edge * scale, edge * scale, body.width - 1 - edge * scale, body.height - 1 - edge * scale), radius=61 * scale, fill=(0, 0, 0, 0))
    body.resize((width + 2 * edge, height + 2 * edge), Image.Resampling.LANCZOS).save(WORK / "body.png")
    return edge


def encode(arguments, target):
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + arguments + ["-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", str(target)], check=True)


def still(picture, seconds, target):
    encode(["-loop", "1", "-t", str(seconds), "-i", str(picture), "-vf", f"scale={SIZE[0]}:{SIZE[1]},format=yuv420p"], target)


def scene(index, clip, seconds, title, line, edge):
    back = shoot(f"caption-{index:02d}", caption(index, title, line))
    target = WORK / f"scene-{index:02d}.mp4"
    graph = (f"[1:v]fps=30,scale={SCREEN[0]}:{SCREEN[1]}:flags=lanczos,tpad=stop_mode=clone:stop_duration=12,trim=duration={seconds},setpts=PTS-STARTPTS,format=rgba[clip];"
             f"[2:v]format=gray[mask];[clip][mask]alphamerge[round];"
             f"[0:v][round]overlay={PLACE[0]}:{PLACE[1]}:shortest=1[on];[on][3:v]overlay={PLACE[0] - edge}:{PLACE[1] - edge}[out]")
    encode(["-loop", "1", "-t", str(seconds), "-i", str(back), "-ss", str(LEAD), "-i", str(RAW / f"{clip}.mov"), "-loop", "1", "-t", str(seconds), "-i", str(WORK / "mask.png"),
            "-loop", "1", "-t", str(seconds), "-i", str(WORK / "body.png"), "-filter_complex", graph, "-map", "[out]", "-t", str(seconds)], target)
    return target, seconds


def join(parts):
    inputs, graph, offset, last = [], "", 0.0, "0:v"
    for index, (path, seconds) in enumerate(parts):
        inputs += ["-i", str(path)]
        if index == 0:
            offset = seconds - FADE
            continue
        graph += f"[{last}][{index}:v]xfade=transition=fade:duration={FADE}:offset={offset:.3f}[x{index}];"
        last = f"x{index}"
        offset += seconds - FADE
    OUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", graph.rstrip(";"), "-map", f"[{last}]", "-r", "30", "-c:v", "libx264", "-preset", "slow",
                    "-crf", "21", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(OUT)], check=True)


if __name__ == "__main__":
    WORK.mkdir(parents=True, exist_ok=True)
    edge = phone_parts()
    parts = []
    opening = WORK / "opening.mp4"
    still(shoot("opening", card("Kairos", "A check-up for your money.", "Concept for the Deutsche Bank case, Futury Build Days")), 2.8, opening)
    parts.append((opening, 2.8))
    for index, (clip, seconds, title, line) in enumerate(SCENES):
        parts.append(scene(index, clip, seconds, title, line, edge))
        print(clip)
    for index, (photo, seconds, title, line) in enumerate(BRANCH):
        target = WORK / f"branch-{index}.mp4"
        still(shoot(f"branch-{index}", branch(photo, title, line)), seconds, target)
        parts.append((target, seconds))
    closing = WORK / "closing.mp4"
    hero = ROOT / "media" / "hero-wide.png"
    still(hero, 4.0, closing)
    parts.append((closing, 4.0))
    join(parts)
    print(OUT)
