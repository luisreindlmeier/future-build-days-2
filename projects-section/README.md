# Kairos — Projects section

The "life projects" part of the Kairos Financial Health Scanner. A client describes
a plan in their own words (a car, a home, a trip, a business, a family, studies, a
sabbatical) and Kairos AI estimates what it costs, what it costs every month, and
whether a bank loan fits. The client's real income, spending and savings decide:
the app computes hard affordability limits itself and enforces them on the AI's answer.

## Run it through the backend

The active integrated backend is `/home/legeant/Desktop/backend`.
Set `OPENAI_API_KEY` in that folder's `.env`, then run:

```bash
cd /home/legeant/Desktop/backend
python3 tools/run_demo.py --components /home/legeant/future-build-days-2
```

Open `http://localhost:5500/index.html?customer=http://localhost:8080/api/users/maya/kairos`.
AI requests now go to `/api/users/{id}/projects/plan`; the backend supplies customer
facts and enforces affordability. The browser does not read `js/secrets.js` or call
AI providers directly. See the active backend's `docs/CONNECTED_API.md` for the contract.

## Customer data

- Default: `test-worst-case.json` — a minimal profile (income, spending, savings,
  inheritance received or only expected).
- Full assessment from the prediction/action agents: open `index.html?customer=input.txt`.

## Files

| File | What it does |
|---|---|
| `js/config.js` | rules, rates, market data, AI providers and models |
| `js/customer.js` | loads the customer file and derives the five vitals |
| `js/engine.js` | `affordability()` — the bank's own limits from the real numbers |
| `js/ai.js` | AI planner prompt, provider calls with fallback, `fixPlan()` re-computes and enforces |
| `js/app.js` | project cards, portfolio, advisor view (donut + mandate moments) |

## Integrated backend demo

See [the demo guide](../docs/DEMO_SETUP.md). With the backend and bridge running, open
`index.html?customer=http://localhost:8080/api/users/maya/kairos`. The connected planner uses the backend-owned OpenAI key.
