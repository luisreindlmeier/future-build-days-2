# Kairos — Projects section

The "life projects" part of the Kairos Financial Health Scanner. A client describes
a plan in their own words (a car, a home, a trip, a business, a family, studies, a
sabbatical) and Kairos AI estimates what it costs, what it costs every month, and
whether a bank loan fits. The client's real income, spending and savings decide:
the app computes hard affordability limits itself and enforces them on the AI's answer.

## Run it

1. Copy `js/secrets.example.js` to `js/secrets.js` and paste your AI key
   (OpenAI `sk-proj-…`, Gemini `AIza…`/`AQ.…`, Groq `gsk_…`, Anthropic `sk-ant-…`).
   `js/secrets.js` is git-ignored — never commit a key.
2. Open `index.html` through a local web server (VS Code **Live Server**, or
   `python -m http.server`). Opening the file directly (`file://`) blocks the AI calls
   and the customer file.

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
