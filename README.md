# Future Build Days — FinPulse / Financial Health Check-Up

- `backend/`: Java 21 / Spring Boot API (tree, scanner, progress, learning) and the Python bridge.
- `prediction-agent/`: Python simulation engine, prediction and action agents, guardrails.
- `projects-section/`: the customer dashboard (static site).

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

Open http://localhost:5500/index.html?user=max (also `maya`, `lena`, `alex`).
Stop with Ctrl+C. Logs are in `backend/data/run/`.

## Where the API keys go

| File | What | Needed? |
|---|---|---|
| `backend/.env` | `OPENAI_API_KEY` (+ optional `OPENAI_MODEL`, `OPENAI_BASE_URL`) | Yes, for live AI wording |
| `prediction-agent/.env` | `HIP_*` gateway key, only when running the agents on their own | Optional |
| `projects-section/js/secrets.js` | browser key for the life-projects planner (copy `secrets.example.js`) | Optional |

All three files are in `.gitignore`. Never commit a real key.
Without a key the demo still runs: the numbers come from the simulation and the text falls back to rule-based wording.

## Tests

```bash
cd backend && mvn test                                     # Java
cd prediction-agent && SKIP_AI=1 python3 -m pytest -q      # Python
```

More detail: [docs/DEMO_SETUP.md](docs/DEMO_SETUP.md), [docs/ACTION_MAPPING.md](docs/ACTION_MAPPING.md) and each component's README.
