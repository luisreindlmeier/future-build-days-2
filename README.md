# Kairos – Financial Health Scanner for Next Gen clients

Future Build Days · Deutsche Bank Wealth Management challenge: *"Design the Financial Health Scanner of the Future for Next Gen clients."*

Kairos shows a customer's financial health as a **Wealth Tree** that grows or shrinks with their real behaviour, explains the future in their own terms with AI agents, and plans life projects (a home, a car, a business) against their real numbers. Every figure comes from code; the AI only puts the numbers into words, and guardrails reject anything it invents.

## What it does

| | |
|---|---|
| **Wealth Tree** | Roots = savings by type, trunk = investments, leaves = spending habits (rotten when far above peers), soil = financial confidence, branches = projects. Health = 50% CFPB well-being percentile + 50% bank-data score. |
| **Assessment** | CFPB Financial Well-Being model (US survey, 2016, n = 5,208, R² 0.57) for confidence, reserves, debt and planning; spending benchmarked against German households with the same income (Destatis, Laufende Wirtschaftsrechnungen 2024). |
| **Prediction agent** | 2,000 seeded Monte Carlo futures per scenario; the AI explains the main goal, the best single change, the biggest risk and the trade-off. |
| **Action agent** | A ranked plan: this week, this month, with your advisor. Investment topics always go to the advisor, never buy/sell instructions. |
| **Memory** | Commit to an action → the bank data verifies it → the tree grows; bad habits that continue make it shrink. Monthly snapshots, milestones (blossoms), history. |
| **Projects** | Describe a plan in your own words; Kairos estimates costs and financing and checks it against the bank's own affordability rules. |

Demo customers: the three personas from the challenge (Lena, 24, first salary · Alex, 29, starting a business · Maya, 31, inheritance) and Max, 26, heir of a family company.

## Repository

```
backend/            Java 21 / Spring Boot API: tree, CFPB scanner, Destatis benchmarks, recommendations,
                    progress memory, and the bridge to the agents (tools/kairos_server.py)
prediction-agent/   Python: simulation engine, prediction agent, action agent, guardrails
projects-section/   Web app: life-project planner (Kairos AI)
```

```
 frontend ──► backend (:8080) ──► tools/kairos_server.py (:8090) ──► engine ──► prediction + action agents
              tree · scanner · benchmarks · memory          (the AI key stays in prediction-agent/.env)
```

## Run it

Requirements: Java 21+, Maven (or IntelliJ), Python 3.9+.

1. **Keys (never commit them)**
   - `prediction-agent/.env` (copy from `.env.example`): `HIP_API_KEY`, `HIP_MODEL`, `HIP_BASE_URL`. Works with the hIP gateway or OpenAI (`HIP_BASE_URL=https://api.openai.com/v1`, `HIP_MODEL=gpt-5-mini`).
   - `projects-section/js/secrets.js` (copy from `secrets.example.js`).
   - Without keys everything still runs: the agents use their rule-based text.
2. **Agents:** `python backend/tools/kairos_server.py --agent-dir prediction-agent` → `live AI: yes`
3. **Backend:** open `backend/` in IntelliJ and run `WealthTreeApplication` (or `mvn spring-boot:run` in `backend/`) → http://localhost:8080/api/users
4. **Projects section:** `cd projects-section && python -m http.server 5500`, then open
   http://localhost:5500/index.html?customer=http://localhost:8080/api/users/maya/kairos
5. **Test everything** (Windows): `powershell -ExecutionPolicy Bypass -File backend/tools/smoke-test.ps1`

API reference and real example responses for every endpoint: [`backend/README.md`](backend/README.md) and [`backend/samples/`](backend/samples/).

## Honest limits

- Demo data only; no real bank connection. Model assumptions (returns, volatility, risk events) are illustrative and must be replaced with the bank's capital-market assumptions.
- The CFPB model is fitted on US data from 2016 with dollar bands; the demo treats € like $.
- Spending benchmarks are Destatis household averages by net-income class; the category mapping is approximate.
- AI text is educational guidance, not investment advice.
