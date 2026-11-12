# FinPulse – Financial Health Check-Up for Next Gen clients

Future Build Days · Deutsche Bank Wealth Management challenge: *"Design the Financial Health Scanner of the Future for Next Gen clients."*

FinPulse shows a customer's financial health as a **Wealth Tree** that grows or shrinks with their real behaviour, explains the future in their own terms with AI agents, and plans life projects (a home, a car, a business) against their real numbers. Every figure comes from code; the AI only puts the numbers into words, and guardrails reject anything it invents.

## What it does

| | |
|---|---|
| **Wealth Tree** | Roots = savings by type, trunk = investments, leaves = spending habits (red when far above peers), soil = financial confidence, flowers = finished learning missions. |
| **Health score (0–100)** | 50% CFPB well-being percentile among peers of the same age + 50% bank-data score (saving 30%, investing 30%, spending 25%, knowledge 15%). The bank half only moves when bank data verifies a change. |
| **Assessment** | CFPB Financial Well-Being model (US survey, 2016, n = 5,208, R² 0.57) for confidence, reserves, debt and planning; spending benchmarked against German households with the same income (Destatis, Laufende Wirtschaftsrechnungen 2024). |
| **Prediction** | Seeded Monte Carlo engine: 2,000 futures per scenario (same habits, each single change, all changes together), reproducible for the same input. The prediction agent explains the main goal, the best change, the biggest risk and the trade-off. |
| **Next steps** | The action agent's ranked plan: this week, this month, with your advisor. Rules choose and rank; the AI writes the words. Investment topics always go to the advisor, never buy/sell instructions. |
| **Learn & grow** | Six two-minute missions personalised to the customer, with a quiz; each finished mission plants a flower on the tree. |
| **Memory** | Commit to an action → the bank data verifies it → the tree grows. Monthly snapshots, history, advisor brief with "book a call". |
| **Life projects** | Describe a plan in your own words; FinPulse AI estimates costs and financing and checks it against the bank's own affordability rules. |

Demo customers: the three personas from the challenge (Lena, 24, first salary · Alex, 29, starting a business · Maya, 31, inheritance) and Max, 26, heir of a family company.

## Repository

```
backend/            Java 21 / Spring Boot API: tree, CFPB scanner, Destatis benchmarks, recommendations,
                    progress memory, learning, and the bridge to the agents (tools/kairos_server.py)
prediction-agent/   Python: simulation engine, prediction agent, action agent, guardrails, tests
projects-section/   Web app: the FinPulse dashboard and the life-project planner
```

```
 dashboard (:5500) ──► backend (:8080) ──► bridge (:8091) ──► engine ──► prediction + action agents ──► guardrails
                       tree · scanner · benchmarks · memory
```

## Run it

You need Java 21+, Maven, Python 3.10+ and Node.js.

```bash
# 1. API key (one key for everything): copy the example and paste your key
cp backend/.env.example backend/.env
#    then edit backend/.env:  OPENAI_API_KEY=sk-...

# 2. Build the backend once
cd backend && mvn package -DskipTests && cd ..

# 3. Start everything (API :8080, AI bridge :8091, dashboard :5500)
python3 backend/tools/run_demo.py --components .
```

Open http://localhost:5500/index.html?user=max (also `maya`, `lena`, `alex`). Stop with Ctrl+C. Logs are in `backend/data/run/`.

## Where the API keys go

| File | What | Needed? |
|---|---|---|
| `backend/.env` | `OPENAI_API_KEY` (+ optional `OPENAI_MODEL`, `OPENAI_BASE_URL`) | Yes, for live AI wording |
| `prediction-agent/.env` | `HIP_*` gateway key, only when running the agents on their own (hIP gateway or OpenAI) | Optional |
| `projects-section/js/secrets.js` | browser key for the life-projects planner (copy `secrets.example.js`) | Optional |

All three files are in `.gitignore`. Never commit a real key. Without a key the demo still runs: the numbers come from the simulation and the text falls back to rule-based wording.

## Tests

```bash
cd backend && mvn test                                     # Java
cd prediction-agent && SKIP_AI=1 python3 -m pytest -q      # Python
```

API reference and example responses: [`backend/README.md`](backend/README.md) and [`backend/samples/`](backend/samples/). More detail: [docs/DEMO_SETUP.md](docs/DEMO_SETUP.md), [docs/ACTION_MAPPING.md](docs/ACTION_MAPPING.md).

## Honest limits

- Demo data only; no real bank connection. Model assumptions (returns, volatility, risk events) are illustrative and must be replaced with the bank's capital-market assumptions.
- The CFPB model is fitted on US data from 2016 with dollar bands; the demo treats € like $. Next step: calibrate on German data (Bundesbank OECD/INFE, PHF).
- The score weights (30/30/25/15) are a transparent design choice, to be recalibrated with outcome data.
- Spending benchmarks are Destatis household averages by net-income class; the category mapping is approximate.
- AI text is educational guidance, not investment advice.
