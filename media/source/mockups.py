#!/usr/bin/env python3
"""Builds the App Store pictures from the raw screenshots: a phone in space, with the part that matters lifted off the screen.

Run from the repository root, after capture.py:  python3 -I media/source/mockups.py [name ...]
Each picture is a small HTML page with CSS 3D transforms, photographed by headless Chrome. Pictures land in media/app-store.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW = ROOT / "ios" / ".build" / "media"
OUT = ROOT / "media" / "app-store"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SHOT = (1206, 2622)

NAVY = "radial-gradient(1500px 1100px at 88% 4%, #3d52e0 0%, rgba(61,82,224,0) 62%), radial-gradient(900px 900px at 0% 100%, #2a2f86 0%, rgba(42,47,134,0) 70%), linear-gradient(165deg, #23277a 0%, #16184b 42%, #0c0e30 100%)"
LIGHT = "linear-gradient(118deg, rgba(255,255,255,0) 42%, rgba(255,255,255,.75) 42.1%, rgba(255,255,255,0) 78%), linear-gradient(180deg, #cfdafb 0%, #e7ecfc 46%, #f7f8fd 100%)"
STORM = "radial-gradient(1300px 900px at 80% 0%, #6672a8 0%, rgba(102,114,168,0) 65%), linear-gradient(170deg, #3a406e 0%, #1c1f4f 50%, #0d0f30 100%)"

# name: background, dark text?, headline, line under it, screenshot, tilt (x, y, z degrees), lifted parts (x, y, w, h in screenshot pixels, lift in px), mascot
PICTURES = {
    "01-health": dict(back=NAVY, dark=False, head="Know how your<br>money is doing.", line="One score. Three rings. Read from your accounts.",
                      shot="home", tilt=(10, -17, 4), lifts=[(48, 350, 1110, 1000, 150)], mascot=None),
    "02-tree": dict(back=LIGHT, dark=True, head="A tree that grows<br>with your money.", line="Leaves are spending, the trunk is investing, the roots are savings.",
                    shot="tree", tilt=(9, 16, -4), lifts=[(48, 590, 1110, 1380, 170)], mascot=None),
    "03-steps": dict(back=NAVY, dark=False, head="Know your<br>next step.", line="See what it changes before you commit to it.",
                     shot="step", tilt=(10, -16, 3), lifts=[(84, 824, 1040, 760, 150), (84, 1632, 1040, 262, 230)], mascot=None),
    "04-films": dict(back=LIGHT, dark=True, head="Explained in<br>two minutes.", line="Paying later, ETFs, your safety net: short films where they matter.",
                     shot="film", tilt=(9, 15, -3), lifts=[(100, 532, 1006, 640, 180)], mascot=None),
    "05-storm": dict(back=STORM, dark=False, head="Test it before<br>the storm does.", line="See whether your savings hold when markets fall.",
                     shot="tree-storm", tilt=(10, -15, 4), lifts=[(48, 590, 1110, 1380, 160)], mascot=None),
    "06-coach": dict(back=LIGHT, dark=True, head="A coach that knows<br>your numbers.", line="Checked figures in plain words. Product advice stays with your advisor.",
                     shot="coach", tilt=(8, 14, -3), lifts=[(40, 1110, 1130, 560, 150)], mascot="mascot-cheer", narrow=True),
    "07-outlook": dict(back=NAVY, dark=False, head="See where you<br>are heading.", line="2,000 simulated futures, with the change and without.",
                       shot="outlook", tilt=(10, -16, 3), lifts=[(48, 680, 1110, 1070, 160)], mascot=None),
}


def page(spec):
    width, bezel = 880, 24
    scale = width / SHOT[0]
    height = round(SHOT[1] * scale)
    ink, soft = ("#12143a", "rgba(18,20,58,.72)") if spec["dark"] else ("#ffffff", "rgba(255,255,255,.78)")
    tilt_x, tilt_y, tilt_z = spec["tilt"]
    shot = (RAW / f"{spec['shot']}.png").as_uri()
    lifts = ""
    for x, y, w, h, lift in spec["lifts"]:
        left, top, wide, high = (round(v * scale) for v in (x, y, w, h))
        lifts += f"""
        <div class="cast" style="left:{left + bezel + 26}px;top:{top + bezel + 60}px;width:{wide}px;height:{high}px"></div>
        <div class="lift" style="left:{left + bezel}px;top:{top + bezel}px;width:{wide}px;height:{high}px;transform:translateZ({lift}px);
             background-image:url('{shot}');background-size:{width}px {height}px;background-position:-{left}px -{top}px"></div>"""
    mascot = ""
    if spec["mascot"]:
        mascot = f"<img class='mascot' src='{(RAW / (spec['mascot'] + '.png')).as_uri()}'>"
    return f"""<!doctype html><meta charset="utf-8">
<style>
  * {{ margin: 0; box-sizing: border-box; }}
  html, body {{ width: 1290px; height: 2796px; overflow: hidden; }}
  body {{ background: {spec['back']}; font-family: -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif; -webkit-font-smoothing: antialiased; position: relative; }}
  h1 {{ position: absolute; left: 96px; top: 190px; right: 60px; font-size: 118px; line-height: 1.03; font-weight: 800; letter-spacing: -3.2px; color: {ink}; }}
  p {{ position: absolute; left: 100px; top: 470px; width: {760 if spec.get("narrow") else 1060}px; font-size: 45px; line-height: 1.28; font-weight: 500; letter-spacing: -0.4px; color: {soft}; }}
  .stage {{ position: absolute; left: 50%; top: 760px; width: 0; height: 0; perspective: 3400px; perspective-origin: 0 900px; }}
  .phone {{ position: absolute; left: -{(width + 2 * bezel) // 2}px; top: 0; width: {width + 2 * bezel}px; height: {height + 2 * bezel}px; transform-style: preserve-3d;
            transform: rotateX({tilt_x}deg) rotateY({tilt_y}deg) rotateZ({tilt_z}deg); }}
  .body {{ position: absolute; inset: 0; border-radius: 142px; background: linear-gradient(140deg, #4a4e6e 0%, #10111f 38%, #2b2e48 100%);
           box-shadow: inset 0 0 0 3px #6a6e92, inset 0 0 0 10px #090a14, 0 90px 140px rgba(4, 6, 34, .55), 0 30px 50px rgba(4, 6, 34, .35); }}
  .screen {{ position: absolute; left: {bezel}px; top: {bezel}px; width: {width}px; height: {height}px; border-radius: 120px; display: block; }}
  .lift {{ position: absolute; border-radius: 46px; box-shadow: 0 0 0 5px rgba(255,255,255,.92), 0 50px 90px rgba(6, 8, 40, .5); }}
  .cast {{ position: absolute; border-radius: 60px; background: rgba(6, 8, 40, .42); filter: blur(38px); transform: translateZ(2px); }}
  .mascot {{ position: absolute; right: 70px; top: 500px; width: 360px; filter: drop-shadow(0 40px 40px rgba(10, 12, 60, .28)); }}
</style>
<h1>{spec['head']}</h1>
<p>{spec['line']}</p>
{mascot}
<div class="stage"><div class="phone">
  <div class="body"></div>
  <img class="screen" src="{shot}">{lifts}
</div></div>
"""


def phone(shot, width, tilt, left, top, lifts=()):
    bezel = round(width * 0.027)
    scale = width / SHOT[0]
    height = round(SHOT[1] * scale)
    source = (RAW / f"{shot}.png").as_uri()
    parts = ""
    for x, y, w, h, lift in lifts:
        a, b, c, d = (round(v * scale) for v in (x, y, w, h))
        parts += f"""<div class="cast" style="left:{a + bezel + 20}px;top:{b + bezel + 46}px;width:{c}px;height:{d}px"></div>
        <div class="lift" style="left:{a + bezel}px;top:{b + bezel}px;width:{c}px;height:{d}px;transform:translateZ({lift}px);
             background-image:url('{source}');background-size:{width}px {height}px;background-position:-{a}px -{b}px"></div>"""
    return f"""<div class="phone" style="left:{left}px;top:{top}px;width:{width + 2 * bezel}px;height:{height + 2 * bezel}px;
        transform:rotateX({tilt[0]}deg) rotateY({tilt[1]}deg) rotateZ({tilt[2]}deg)">
      <div class="body" style="border-radius:{round(width * 0.161)}px"></div>
      <img class="screen" src="{source}" style="left:{bezel}px;top:{bezel}px;width:{width}px;height:{height}px;border-radius:{round(width * 0.136)}px">{parts}</div>"""


def wide():
    mascot = (RAW / "mascot-smile.png").as_uri()
    return f"""<!doctype html><meta charset="utf-8">
<style>
  * {{ margin: 0; box-sizing: border-box; }}
  html, body {{ width: 2880px; height: 1620px; overflow: hidden; }}
  body {{ background: {NAVY}; font-family: -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif; -webkit-font-smoothing: antialiased; position: relative; color: #fff; }}
  .name {{ position: absolute; left: 170px; top: 300px; font-size: 76px; font-weight: 700; letter-spacing: -1px; display: flex; align-items: center; gap: 26px; }}
  .name img {{ width: 150px; }}
  h1 {{ position: absolute; left: 170px; top: 520px; width: 1150px; font-size: 150px; line-height: 1.02; font-weight: 800; letter-spacing: -4.5px; }}
  p {{ position: absolute; left: 176px; top: 900px; width: 980px; font-size: 52px; line-height: 1.3; font-weight: 500; color: rgba(255,255,255,.78); }}
  .note {{ position: absolute; left: 176px; top: 1400px; font-size: 34px; font-weight: 500; color: rgba(255,255,255,.55); }}
  .stage {{ position: absolute; left: 0; top: 0; width: 2880px; height: 1620px; perspective: 4200px; perspective-origin: 2000px 700px; transform-style: preserve-3d; }}
  .phone {{ position: absolute; transform-style: preserve-3d; }}
  .body {{ position: absolute; inset: 0; background: linear-gradient(140deg, #4a4e6e 0%, #10111f 38%, #2b2e48 100%);
           box-shadow: inset 0 0 0 3px #6a6e92, inset 0 0 0 9px #090a14, 0 90px 140px rgba(4, 6, 34, .6), 0 30px 50px rgba(4, 6, 34, .35); }}
  .screen {{ position: absolute; display: block; }}
  .lift {{ position: absolute; border-radius: 38px; box-shadow: 0 0 0 4px rgba(255,255,255,.92), 0 46px 80px rgba(6, 8, 40, .5); }}
  .cast {{ position: absolute; border-radius: 50px; background: rgba(6, 8, 40, .42); filter: blur(32px); transform: translateZ(2px); }}
</style>
<div class="name"><img src="{mascot}">Kairos</div>
<h1>A check-up for your money.</h1>
<p>One score, a tree that grows with you, and a plan your bank data can check.</p>
<div class="note">Concept for the Deutsche Bank case, Futury Build Days</div>
<div class="stage">
  {phone("tree", 540, (8, -24, 5), 1270, 400)}
  {phone("step", 560, (8, -24, 5), 2400, 250)}
  {phone("home", 640, (8, -24, 5), 1830, 110, [(48, 350, 1110, 1000, 130)])}
</div>
"""


def branch():
    """The terminal in the branch and the phone it hands over to."""
    photo = (ROOT / "media" / "terminal" / "05-code.jpg").as_uri()
    return f"""<!doctype html><meta charset="utf-8">
<style>
  * {{ margin: 0; box-sizing: border-box; }}
  html, body {{ width: 1290px; height: 2796px; overflow: hidden; }}
  body {{ background: {NAVY}; font-family: -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif; -webkit-font-smoothing: antialiased; position: relative; }}
  h1 {{ position: absolute; left: 96px; top: 190px; right: 60px; font-size: 118px; line-height: 1.03; font-weight: 800; letter-spacing: -3.2px; color: #fff; }}
  p {{ position: absolute; left: 100px; top: 470px; width: 1060px; font-size: 45px; line-height: 1.28; font-weight: 500; letter-spacing: -0.4px; color: rgba(255,255,255,.78); }}
  .photo {{ position: absolute; left: 70px; top: 730px; width: 1150px; height: 1120px; border-radius: 70px; background: url('{photo}') 12% 50% / cover;
            box-shadow: 0 0 0 6px rgba(255,255,255,.9), 0 70px 110px rgba(4, 6, 34, .55); transform: rotate(-2deg); }}
  .stage {{ position: absolute; left: 0; top: 0; width: 1290px; height: 2796px; perspective: 3400px; perspective-origin: 900px 2000px; }}
  .phone {{ position: absolute; transform-style: preserve-3d; }}
  .body {{ position: absolute; inset: 0; background: linear-gradient(140deg, #4a4e6e 0%, #10111f 38%, #2b2e48 100%);
           box-shadow: inset 0 0 0 3px #6a6e92, inset 0 0 0 9px #090a14, 0 90px 140px rgba(4, 6, 34, .6), 0 30px 50px rgba(4, 6, 34, .35); }}
  .screen {{ position: absolute; display: block; }}
</style>
<h1>Start at the branch.<br>Go on at home.</h1>
<p>The same check-up at a self-service terminal, handed to your phone by code.</p>
<div class="photo"></div>
<div class="stage">{phone("home", 600, (8, -14, 5), 600, 1420)}</div>
"""


def render_wide():
    pages = RAW / "mockups"
    pages.mkdir(parents=True, exist_ok=True)
    source = pages / "hero-wide.html"
    source.write_text(wide())
    target = ROOT / "media" / "hero-wide.png"
    subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1", "--window-size=2880,1620",
                    "--virtual-time-budget=3000", f"--screenshot={target}", source.as_uri()], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    print(target)


def render(name, spec):
    pages = RAW / "mockups"
    pages.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    source = pages / f"{name}.html"
    source.write_text(page(spec))
    subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1", "--window-size=1290,2796",
                    "--virtual-time-budget=3000", f"--screenshot={OUT / (name + '.png')}", source.as_uri()],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    print(OUT / f"{name}.png")


if __name__ == "__main__":
    wanted = sys.argv[1:] or list(PICTURES) + ["08-branch", "hero-wide"]
    for name in wanted:
        if name == "hero-wide":
            render_wide()
        elif name == "08-branch":
            pages = RAW / "mockups"
            (pages / "08-branch.html").write_text(branch())
            subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1", "--window-size=1290,2796", "--virtual-time-budget=3000",
                            f"--screenshot={OUT / '08-branch.png'}", (pages / "08-branch.html").as_uri()], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            print(OUT / "08-branch.png")
        else:
            render(name, PICTURES[name])
