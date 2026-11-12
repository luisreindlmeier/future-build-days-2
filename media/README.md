# Kairos: pictures and film

What we show of the iPhone app in `ios/` and of the check-up at a terminal in the branch. Everything here is made
from the running app, and the scripts in `source/` build it again.

| Where | What |
|---|---|
| `app-store/` | Eight portrait pictures in App Store format (1290 by 2796): a phone in space, with the part that matters lifted off the screen. |
| `hero-wide.png` | A wide picture with three phones (2880 by 1620), for slides. |
| `demo/kairos-demo.mp4` | A walk through the app in 72 seconds (1920 by 1080, no sound). |
| `terminal/` | Seven pictures of a check-up at a self-service terminal, from walking in to the advisor. |
| `source/` | The scripts, and the scenes of the branch they start from. |

## The story at the terminal

| Picture | What happens |
|---|---|
| `01-arrive.jpg` | She walks in and the terminal asks how her money is doing. |
| `02-agree.jpg` | She sees what the check reads, and agrees. |
| `03-check.jpg` | The check runs: accounts, peers, well-being, simulation. |
| `04-result.jpg` | Her tree and her rings. No amounts on the shared screen. |
| `05-code.jpg` | She scans the code to take the check-up with her. |
| `06-phone.jpg` | The figures and the plan open on her own phone. |
| `07-advisor.jpg` | An advisor comes over, already briefed by the summary. |

## How it is made

You need Xcode, Google Chrome, ffmpeg and Python 3 with Pillow. Run everything from the repository root.

1. `ios/scripts/sim.sh run` builds the app and starts it in a simulator of its own.
2. `python3 -I media/source/capture.py shots` takes the screenshots, `clips` records one short clip per screen.
   The app's launch arguments do the driving (`ios/Kairos/Router.swift`). For the terminal, run
   `SIM_DEVICE=pad ios/scripts/sim.sh install` and then `capture.py pad`.
3. `python3 -I media/source/mockups.py` builds `app-store/` and `hero-wide.png`. Each picture is a small HTML page
   with CSS 3D transforms, photographed by headless Chrome.
4. `python3 -I media/source/terminal.py` fits the terminal's screens into the scenes in `source/scenes/`: it finds
   the green screen, places the screenshot in perspective and keeps what is in front of it, a finger for example.
5. `python3 -I media/source/film.py` cuts the film with ffmpeg.

The raw screenshots and clips land in `ios/.build/media` and are not checked in.

## Good to know

- The scenes of the branch are generated images, and the people in them do not exist. The screens on the terminal
  and on the phone are real screenshots of the app.
- The figures are those of the demo customer Maya, from the backend's saved answers.
- The short films in the app have a cover and a summary. They are not recorded.
