# Prediction agent

`prediction_agent.py` explains, for one customer, what can happen if they keep their habits and what can happen if they change them, measured against their goals. Standard library only, Python 3.9+.

## Use it
```python
from prediction_agent import predict
res = predict(engine_json)   # contract: top of prediction_agent.py, example: example_input.json
res["source"]    # "ai" or "fallback"
res["output"]    # headline, if_nothing_changes, best_change, comparison, disclaimer
res["problems"]  # validator messages when the AI answer was rejected
```
Try it: `python3 prediction_agent.py example_input.json`

## Setup
Copy `.env.example` to `.env`, put the hIP key after `HIP_API_KEY=`. Never commit `.env`.

## Rules the code enforces
- The engine produces all numbers (as display strings); the agent only copies them.
- Every EUR and % figure in the answer must appear in the input. No "N of 10" conversions.
- `best_change` is checked against the engine: highest goal chance among single changes.
- Scenario ids must exist; comparison must cover every non-baseline scenario.
- No promise or advice wording; exact disclaimer sentence.
- One automatic retry that tells the model what was wrong; after that a deterministic fallback text built from the same numbers. The product never shows unchecked AI text.

## What your side must provide
The simulation engine and intake: one `baseline` scenario ("same habits"), one `change` scenario per habit change, optional `combo`, each with `range`, `middle`, `weak_future`, `risk_below_today`, `goal_success` per goal. The demo's engine (`checkup-demo.html`, seeded Monte Carlo) generated `example_input.json`.
