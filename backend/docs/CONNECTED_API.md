# Connected backend contract

Work from `/home/legeant/Desktop/backend`. The teammate components currently live in
`/home/legeant/future-build-days-2/prediction-agent` and `projects-section`.
The backend's Python bridge runs both agents and the projects planner. Node.js runs
the team's existing JavaScript prompt, customer conversion and affordability checks
on the server. The browser never supplies authoritative financial figures or AI prompts.

## One key and one start command

Edit `backend/.env` (next to pom.xml):

```
OPENAI_API_KEY=your-openai-key
OPENAI_MODEL=gpt-4.1-mini
OPENAI_BASE_URL=https://api.openai.com/v1
```

Do not put a key in the browser. Legacy prediction-agent/.env and js/secrets.js are
not used by this launch flow. Process environment variables override backend/.env.
The public asset server refuses to serve js/secrets.js, dotfiles and arbitrary files.
Restart after changing the key/model so cached assessments are refreshed.

Requires Java 21, Maven, Python 3.9+ and Node.js (tested with the installed Node runtime).

```bash
cd /home/legeant/Desktop/backend
mvn package
python3 tools/run_demo.py --components /home/legeant/future-build-days-2
```

Ctrl+C stops all components. Logs are in `data/run/`. The bridge is private on 8091,
Java is on 8080, and the projects page is on 5500. All bind to loopback.
Open `http://localhost:5500/index.html?customer=http://localhost:8080/api/users/maya/kairos`.

## UI endpoints (all on port 8080)

- `GET /api/users`: persona picker.
- `GET /api/users/{id}/workspace`: tree, assessment, progress, prediction (including
  action-agent output), actionMappings and saved projects. Poll while
  `prediction.status` is RUNNING. UNAVAILABLE means the bridge needs attention.
- `GET /api/users/{id}/kairos`: complete assessment in the team's projects format.
- `POST /api/users/{id}/projects/plan`: generate a project estimate. Body below.
- `POST /api/users/{id}/projects`: explicitly save a project using the existing backend
  project schema (`name`, `type`, `targetAmount`, `savedAmount`, `targetDate`). Planning
  alone does not commit savings or create a stored project.
- `POST /api/users/{id}/actions/{actionId}/commit` and `/drop`: accept supported agent
  aliases. Join agent action_id to workspace.actionMappings, use canCommit, and display
  that mapping's action title/amounts before committing. Unsupported agent advice stays
  advice; do not invent tree actions for it.
- `POST /api/users/{id}/advance-month?months=1`: verify demo actions and update facts.
  Fetch workspace again to trigger refreshed predictions.

```json
{"type":"trip","name":"Japan","description":"Two weeks in Japan next year"}
```

Planning types: car, home, business, studies, trip, family, sabbatical.
The server loads the live customer assessment and derives income, cash, saving capacity,
coaching context and affordability; client-supplied financial fields are ignored.
Description is required (max 1500 characters), name max 120. Invalid inputs return 400;
unknown customer 404; unavailable assessment/bridge 503.

Success: `source: "ai"`, `plan` (the team's validated display shape), `targetM`,
and `affordability`. Loan limits and savings caps are enforced on the server.
No key, provider failure or invalid AI output: `source: "rules"`, `plan: null`,
`affordability` and `message`. Show the constraints and unavailable estimate honestly;
this is not a completed AI estimate. Python prediction/action agents independently
return ai, ai_partial or fallback in their existing source fields.

Tree recommendations, scanner calculations, progress and situation keyword rules stay
deterministic. This connection does not replace financial calculations with an LLM.
The November 2026 rates and prices remain the team's demo assumptions.

## Customer-made profiles (all on port 8080)

- `GET /api/profiles`: demo customers and created profiles (`custom: true`) for the picker.
- `POST /api/profiles`: create a profile from the onboarding form (`ProfileRequest`: name, age, lifeStage
  pro|founder|heir, purpose, situation, riskTolerance, monthlyIncome, spending per category, cashSavings,
  investments, companyShares, monthlySavingCash/Invested, crashReaction sell|hold|buy, disabilityCover, will,
  confidence 1-5, knowledge 1-7, shockAbsorb 1-4, horizonYears, 1-2 goals wealth|home|keep, subscriptions,
  plannedPurchases). Returns `{id, name, age, custom}` and starts the agents. Invalid input: 400 with a reason.
- `GET /api/profiles/{id}`: the form for any customer (a demo customer as a starting point to copy).
- `PUT /api/profiles/{id}`: personalise a created profile; its progress memory starts over and the agents re-run.
  Demo customers are read-only (400).
- `DELETE /api/profiles/{id}`: created profiles only.

Created profiles get the same tree, scanner, progress, predictions, actions and projects as the demo customers.
They are saved in `data/custom-profiles.json` and survive restarts and `/api/demo/reset`.
The dashboard adds "AI agents at work" (each step with timing, the facts sent, every attempt and what the
guardrail caught), "Create a profile" and "Personalise".

## Checks

`mvn test` covers the Java pipeline and action aliases.
`python3 tools/test_connections.py` tests the project connection without external calls,
including malformed AI output and enforcement of loan/saving limits.
Live AI needs an actual configured key and a separate rehearsal.
