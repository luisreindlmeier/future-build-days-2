# Wealth Tree – backend (Spring Boot)

Backend for the **Wealth Tree**: it turns a user's financial data and personal context into
an assessment, recommendations (linked to bank products and learning modules), a prediction,
and one `TreeState` JSON that the 2.5D frontend renders. No auth, no database: three demo personas
(Lena, Alex, Maya from the challenge, plus Max from the team demo) live in memory.

## Pipeline

```
Data inputs ─────────────┐                        ┌─> Recommendations ─> Actions (bank products)
 savings pots            │                        │                   └> Knowledge trainings
 user data / income      ├─> Assessment ──────────┤
 portfolio (holdings)    │   (scores 0-100,       └─> Prediction (simulate N months)
 transactions            │    habits, findings)
Non-deterministic inputs ┘            │
 goals, own situation, age, risk      └──────────────> TreeState (roots, trunk, leaves, branches, soil, weather)
Projects (house, travel...) ──────────────────────────> branches
```

| Tree part | Comes from | Key fields |
|---|---|---|
| **Roots** (one per savings category: Safety, Goal, Deep/retirement, Anchor/protection) | savings pots, project savings | `depth`, `thickness`, `health`, `status` |
| **Trunk** | portfolio | `thickness`, `height`, `rings` (years of consistency), `cracks` (risks), `stability` |
| **Leaves** (one cluster per spending category) | transactions | `size` (scales with spending), `leafCount`, `health` HEALTHY/WILTING/ROTTEN, `rottenRatio` |
| **Branches** | projects | `length` (= progress), `angleDeg`, `fruit` (funded), `blossom` (≥50%) |
| **Soil** | knowledge check + completed trainings | `richness`, `layers` |
| **Weather** | situation (e.g. variable income) | `CALM / BREEZY / WINDY / STORM` |
| **Stage** | total wealth | `SAPLING / YOUNG / MATURE` → which sprite set to use |

All visual values are normalised **0..1**, so the frontend only maps them to sprites, sizes and animations.
Every part also has a `detail` sentence for the tap-to-inspect panel.

## Run

Requires Java 21 and Maven.

```bash
mvn spring-boot:run          # http://localhost:8080
mvn test                     # core pipeline tests
```

## API

| Method | Path | What |
|---|---|---|
| GET | `/api/users` | Personas with headline and health |
| GET | `/api/users/{id}` | Raw inputs |
| GET | `/api/users/{id}/assessment` | Scores, habits, findings, interpreted context |
| GET | `/api/users/{id}/tree` | **Main endpoint**: the `TreeState` to render |
| GET | `/api/users/{id}/recommendations` | Recommendations with action, product, training, predicted gain |
| POST | `/api/users/{id}/simulate` | Prediction. Body `{"actionIds":["act-buffer"],"months":12}`. Omit `actionIds` = apply all; `[]` = do nothing |
| POST | `/api/users/{id}/storm` | Storm (market crash) test result for the animation |
| PUT | `/api/users/{id}/context` | Update age, `riskTolerance` (CAUTIOUS/BALANCED/GROWTH), `situation`, `goals` |
| POST | `/api/users/{id}/projects` | Add/update a project `{"name":"Trip to Japan","type":"TRAVEL","targetAmount":4000,"savedAmount":300,"targetDate":"2027-12-01"}` |

Ids: `lena`, `alex`, `maya`, `max`. Example responses are in [`samples/`](samples/) so the frontend can start before the backend runs.

```bash
curl localhost:8080/api/users/maya/tree
curl -X POST localhost:8080/api/users/maya/simulate -H 'Content-Type: application/json' -d '{"months":12}'
```

## Financial Health Scanner (assessment, CFPB well-being model)

`scanner/FinancialHealthScanner` is a 1:1 port of the team's `score.py`. It reads the same
`src/main/resources/scanner/model_params.json` and passes the team's `test_cases.json`
(`ScannerParityTest`). See `src/main/resources/scanner/SCANNER_README.md` for the model, the items and the caveats.

| Scanner output | Where it shows in the tree |
|---|---|
| `reserves` | health of the safety roots |
| `planning_protection` | health of the deep (retirement) and anchor (protection) roots |
| `debt` | `trunk.barkHealth`; below 50 adds a crack |
| `confidence_skill` | soil richness |
| `predicted_score_percentile` | half of `overallHealth` (the other half is the bank-data score) |
| everything | `tree.wellbeing` (predicted CFPB score, percentiles, habits, warnings) |

- Questionnaire answers are hardcoded per customer in `scanner/ScannerAnswers` (CFPB PUF codes).
- Each recommendation gets `wellbeingGain`: the scanner's what-if for the answers that action would change
  (mapping and assumptions in `ScannerAnswers.changeFor`). `null` when the questionnaire can't measure it.
- The prediction view ("with the plan") re-scores the questionnaire with all completed actions.
- Caveat for the pitch: the model is fitted on US data from 2016 with dollar bands; the demo treats € like $.

| Method | Path | What |
|---|---|---|
| GET | `/api/users/{id}/scanner` | Same output as `score.py` |
| GET | `/api/users/{id}/scanner/answers` | The questionnaire answers |
| POST | `/api/users/{id}/scanner/what-if` | Body `{"SAVINGSRANGES": 5}` → same output as `what_if()` |

## How everything links together (Kairos)

```
                         ┌──────────────────────── Java backend (this project, :8080) ───────────────────────┐
 bank data, Destatis,    │ tree · scanner (CFPB) · benchmarks · recommendations · memory (progress)          │
 questionnaire ────────► │                                                                                    │
                         │ kairos/IntakeBuilder: live data -> the team's customer intake ───────┐             │
                         └──────────────────────────────────────────────────────────────────────┼─────────────┘
                                                                                                  │ POST /assessment
                         ┌──────── prediction-agent (team, Python) via tools/kairos_server.py (:8090) ─────────┐
                         │ engine.py (Monte Carlo) ─► prediction_agent.py + action_agent.py (in parallel)     │
                         └─────────────────────────────────────────────────────────────────────────────────────┘
 Frontends: the tree app reads /api/users/{id}/tree, /prediction, /history …
            the projects section reads /api/users/{id}/kairos (same JSON as its input.txt)
```

- **One customer, one source of truth.** `IntakeBuilder` turns each customer's live data into the team's intake
  (`engine.EXAMPLE_CUSTOMER` + `spending`): wealth, cash, company share, spending, saving habit (+ committed
  standing orders), crash reflex, cover, buffer/diversification plans (from verified actions), goals,
  wants vs **Destatis peers** (sent as `peer_median`), subscriptions. Extras the bank data can't know
  (profile, purpose, crash reflex, will, subscriptions' last use) are in `kairos/KairosPersonas`.
- **Max is identical to the team's `EXAMPLE_CUSTOMER`** (€490k, €3,100 cash, 82% company, 40% goal chance).
- **Predictions follow the tree.** The cache key is the intake: when a month passes or an action is verified,
  the next request runs the team's pipeline again (e.g. Maya's buffer and cover scenarios disappear once done).
- The **AI only ever sees "Customer"**; the real first name is added back for the projects section.
- The Java Monte Carlo port (`forecast/`) stays as an **offline fallback** (`/forecast/agent-input`, and
  `/forecast/chart` when the bridge is down). The team's `engine.py` 1.1 is the source of truth.

### Run it (3 terminals)

```bash
# 1. the team's agents (Python 3.9+); the key stays in prediction-agent/.env
python backend/tools/kairos_server.py --agent-dir prediction-agent      # http://localhost:8090
# 2. this backend
cd backend && mvn spring-boot:run                                         # http://localhost:8080
# 3. projects section (VS Code Live Server or python -m http.server in projects-section), then open:
#    index.html?customer=http://localhost:8080/api/users/maya/kairos
```

Without a key, both agents return their rule-based text, so everything works offline.

### Endpoints for the frontend

| Method | Path | Use |
|---|---|---|
| GET | `/api/users` | persona picker (lena, alex, maya, max) |
| GET | `/api/users/{id}/tree` | **the tree** (roots, trunk, leaves, branches, soil, weather, blossoms, wellbeing, progress) |
| GET | `/api/users/{id}/recommendations` | recommendations (why, action, product, training, CFPB gain) |
| POST | `/api/users/{id}/actions/{actionId}/commit` | commit to an action |
| POST | `/api/users/{id}/advance-month?months=1` | demo time machine: events + new tree |
| GET | `/api/users/{id}/history` · `/progress` | timeline chart · trend |
| GET | `/api/users/{id}/scanner` · `/scanner/answers` · POST `/scanner/what-if` | CFPB scanner |
| GET | `/api/users/{id}/intake` | what is sent to the team's engine |
| GET | `/api/users/{id}/prediction` | engine + `chart` + prediction agent + action agent (`RUNNING` → poll) |
| GET | `/api/users/{id}/kairos?wait=60` | projects-section format; waits for the result |
| GET | `/api/users/{id}/forecast/chart` | fan chart (team engine; Java fallback offline) |
| POST | `/api/users/{id}/storm` · `/simulate` | storm test · 12-month projection |
| POST | `/api/demo/reset` | back to the demo data |

Real responses for every persona are in [`samples/`](samples/) (`*-tree`, `*-prediction`, `*-kairos`, `*-intake`, …),
so the frontend can be built before the backend runs.

## Code map

```
model/           inputs: profile, pots, holdings, transactions, projects
assessment/      Assessor (deterministic scores) + SituationInterpreter (non-deterministic inputs)
recommendation/  RecommendationEngine, Catalog (products + trainings)
projection/      ProjectionService (prediction / "with your plan")
tree/            TreeBuilder -> TreeState (+ storm test)
forecast/        MonteCarloEngine, ForecastProfiles, AgentInputBuilder (prediction agent input)
prediction/      PredictionService + HttpKairosBridge (calls the team's Python pipeline)
kairos/          IntakeBuilder (live data -> team intake), KairosPersonas (profile extras)
scanner/         FinancialHealthScanner (port of score.py), ScannerAnswers, WellBeing
progress/        ProgressService (months, verification, snapshots, milestones), FileStateStore
data/            in-memory repository + demo personas
app/, api/       Spring Boot wiring and REST controllers
tools/           kairos_server.py: HTTP bridge to the team's engine + prediction agent + action agent
```

The core (`model` → `tree`) has **no Spring dependency**, so it's easy to test and to explain.

## Memory: the tree grows and shrinks over time

`progress/ProgressService` remembers every user and saves everything to `data/wealth-tree-state.ser`
(survives restarts; delete it or call `POST /api/demo/reset` to start over).

Rule: **only inputs change; every score is recalculated** (nothing is updated by hand). Each month:
1. **Spending** continues the user's own pattern (half of the recent trend), so bad habits keep growing unless a limit is committed.
2. **Committed actions run** and are **verified only when the data shows them**: a standing order arrives, an investment step executes,
   a category stays under its limit, the advisor confirms cover. On verification the questionnaire answers update too.
3. Money left over lands on the current account; a shortfall comes out of the safety pot.
4. **Markets move** (seeded): investments can fall, so the trunk can shrink.
5. **Facts are re-derived** from the data (savings band, products held); self-assessed answers change only through actions or a new check-up.
6. A full year with ≥10 invested months adds a **ring**.
7. The tree is recalculated and compared with last month; a **snapshot** stores the vital signs and what changed in plain words
   ("Eating out leaves recovered: rotten → wilting"). **Milestones** become permanent blossoms.

Tree health = 50% CFPB peer percentile (what you tell us) + 50% bank-data score (what your accounts show).
Example over 12 months: Maya with a plan 49 → 68, doing nothing 49 → 44.

| Method | Path | What |
|---|---|---|
| POST | `/api/users/{id}/actions/{actionId}/commit` | Commit to a recommended action (e.g. `act-limit-eating_out`) |
| POST | `/api/users/{id}/actions/{actionId}/drop` | Drop it |
| POST | `/api/users/{id}/advance-month?months=1` | Demo time machine: returns each month's events and the new tree |
| GET | `/api/users/{id}/history` | All snapshots (for a timeline chart), actions with status, milestones |
| GET | `/api/users/{id}/progress` | Trend (GROWING / STABLE / SHRINKING), change last month and since start, latest events |
| POST | `/api/demo/reset` | Back to the original demo data |

The tree JSON now also has a `progress` block with the same summary.

## Benchmarks: when is a behaviour good or bad?

| Behaviour | Benchmark | Source |
|---|---|---|
| **Spending per category (leaves)** | Compared with the average of households in the **same net-income class** | **Destatis, Laufende Wirtschaftsrechnungen 2024** (`assessment/SpendingBenchmarks`) |
| Leaf health | healthy up to 1.25× the peer average; wilting above that or when growing ≥25%; rotten above 1.75×, or above 1.25× and growing ≥40%. Rent and groceries can only wilt. | thresholds are ours |
| Scanner dimensions (roots' health, bark, soil) and overall health | Percentile among peers of the same **age band** | CFPB National Financial Well-Being Survey 2016 (team's scanner) |
| Emergency buffer | 3–6 months of spending | Common financial-planning guideline |
| Savings rate / wants | 20% saved, wants ≤30% of income | 50/30/20 rule |
| Concentration | one position ≤30% (family company: down to 60% step by step) | Diversification rule of thumb / team demo |

Destatis table (EUR per household and month, 2024), used as-is:

| Category (Destatis group) | <€1,300 | €1,300–2,600 | €2,600–3,600 | €3,600–5,000 | €5,000+ |
|---|---|---|---|---|---|
| Housing (Wohnen, Energie) | 605 | 816 | 1,064 | 1,271 | 1,666 |
| Groceries (Nahrungsmittel, Getränke) | 238 | 306 | 403 | 502 | 652 |
| Transport (Verkehr) | 111 | 204 | 354 | 468 | 787 |
| Eating out (Gastronomie und Beherbergung) | 62 | 102 | 160 | 226 | 378 |
| Shopping (Bekleidung + Innenausstattung) | 86 | 135 | 215 | 272 | 437 |
| Travel & leisure (Freizeit, Sport und Kultur) | 76 | 147 | 246 | 309 | 545 |
| Subscriptions (Information und Kommunikation) | 72 | 104 | 126 | 148 | 192 |
| Other (Andere Waren und Dienstleistungen) | 41 | 63 | 93 | 108 | 169 |

Source page: https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Einkommen-Konsum-Lebensbedingungen/Konsumausgaben-Lebenshaltungskosten/Tabellen/liste-monatlichen-haushalts-nettoeinkommen.html

Caveats: the classes are *household* income and richer households are on average larger, so for single people the benchmark is generous; the category mapping is approximate (eating out includes hotels, travel includes all leisure).

Other methodology:
- Overall (bank-data) score = 30% savings + 30% investing + 25% spending + 15% knowledge; with the scanner, tree health is the CFPB peer percentile.
- Investing: invested share, diversification (1 − HHI; broad funds count as diversified), consistency (months invested of the last 12).
- Projection replays recent spending, applies committed actions, grows investments at an illustrative return per risk profile.

## Next steps

- `SituationInterpreter`: replace the keyword version with an LLM call that returns the same `SituationContext`.
  Keep numbers in code; let the LLM only interpret text and phrase explanations.
- `Catalog`: replace placeholder product names with the real Deutsche Bank products.
- Swap `InMemoryUserRepository` for real data (open banking) when needed.
