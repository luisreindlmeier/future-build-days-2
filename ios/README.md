# Kairos for iPhone and iPad

The native front end to the Kairos backend. It shows the same customers, the same figures and the same plan as the
web dashboard in `projects-section/`, in its own design, and adds the branch terminal: on an iPad the app starts as
a self-service check-up that hands over to the phone by QR code.

SwiftUI, iOS 26, Swift 6, no dependencies. `project.yml` (XcodeGen) is the source of truth; the Xcode project is
generated and not checked in.

## Run it

1. Start the backend as described in the repository README (`python3 backend/tools/run_demo.py --components .`).
2. `cd ios && xcodegen generate && open Kairos.xcodeproj`, then run on a simulator. The simulator reaches the
   backend at `http://localhost:8080`.
3. On a real iPhone, tap the initial at the top left of Home and enter the Mac's address
   (`http://<the Mac's IP>:8080`) under Backend.

Without a backend the app opens on a saved copy of the backend's answers (`Kairos/Resources/Snapshots/`), so it
can always be shown. Committing, dropping, saving a project and advancing a demo month need the backend.

`scripts/sim.sh build | run | screens <dir> <screen>... | test | clean` builds and runs in a simulator of its own
(`SIM_DEVICE=pad` for the terminal). Screens for `-screen`: `onboarding`, `onboarding-customer`,
`onboarding-consent`, `onboarding-scan`, `onboarding-reveal`, `onboarding-findings`, `score`,
`category-<spending|saving|investing>`, `area-<category>`, `prediction`, `tree`, `plan`, `action`, `film-<id>`,
`coach` (`-ask <question_with_underscores>`), `profile`, `advisor`, `terminal`, `terminal-customer`,
`terminal-consent`, `terminal-scan`, `terminal-result`, `terminal-handoff`, `terminal-advisor`. They read the saved
copy; add `-live` to read the backend, `-user <id>` to pick the customer, `-part <trunk|soil|leaf:ID|root:ID|storm>`
to choose a part of the tree, `-scroll films` to move a page down to its films.

Pictures and a film of the app are in `media/`, with the scripts that make them.

## How it maps to the backend

Everything comes from `GET /api/users/{id}/workspace`; the app computes no figures of its own.

| In the app | From the backend |
|---|---|
| Financial health, the big number | `tree.overallHealth`, the same number as the dashboard |
| The three rings: Spending, Saving, Investing | `assessment.spendScore`, `savingsScore`, `investScore` |
| Rows under Spending | `tree.leaves` (health, peers, detail) |
| Rows under Saving | `tree.roots` |
| Rows under Investing | `tree.trunk` (thickness, stability, rings, cracks) |
| Tree tab | the whole `TreeState`, built in space and seen from the front corner; storm test from `POST /storm` |
| Your outlook | `prediction.prediction.output` and `prediction.chart` |
| Plan: next steps | `prediction.actions.output.actions`, joined to `actionMappings` |
| Commit, drop, advance a month | `POST /actions/{id}/commit`, `/drop`, `/advance-month`, as in the dashboard |
| Life projects | `projects`, `POST /projects` |
| Coach | the agents' own sentences, picked by question; no second model on top |
| Explained in two minutes | the topics of the dashboard's learning missions (`projects-section/js/learn.js`), plus paying later and ETFs: a cover and a summary, shown with the step or the area they explain |

Ratings follow the backend's steps (`PartStatus.of`): 75 and up is strong, 40 and up growing, below needs care.
They are drawn in three blues, light to deep. The tree keeps the colours of the dashboard's tree: a bough is lush
when spending is in line, yellowing when it is above peers, thin and brown with falling leaves when it is far
above. Knowledge shows as the soil of the tree.

## Layout of the code

- `Kairos/API/`: the response models as the backend sends them, the client, the saved copy.
- `Kairos/Presentation.swift`: turns a workspace into the three categories and their rows.
- `Kairos/Features/`: Onboarding, Home (with categories and outlook), Tree, Plan, Learn, Coach, Profile, Terminal.
- `Kairos/Features/Tree/`: `TreeModel` builds the tree from `TreeState` as faces and round lumps in space;
  `Scene3D` is the small renderer that lights them, sorts them and paints them into a SwiftUI canvas, seen from
  the front corner without perspective; `TreeCanvas` turns it by drag, picks the part under a tap and lets it sway.
- `Kairos/DesignSystem/`, `Kairos/Components/`: navy and blue on a light page, one blue spectrum for ratings,
  Lucide icons, the mascot, which breathes, blinks and hops. Drawings are cut from `design/illustrations/` by
  `tools/slice_illustrations.py`.
- `KairosTests/`: decodes every saved copy and checks the mapping.

## Not there yet

- The AI project planner (`POST /projects/plan`).
- The learning missions of the dashboard with their questions and flowers. The app shows what each short film
  covers; the films are not recorded.
- Creating a customer profile from the onboarding form (`POST /api/profiles`).
- A real consent record: the consent screen informs and asks, the backend has no consent yet.
