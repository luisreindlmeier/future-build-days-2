# Prediction agent (v2)

Tells one customer what can happen if they keep their habits and what can happen if they change them, measured against their own goals. Python 3.9+, standard library only.

## What it returns
- **headline / if_nothing_changes**: the main goal and its chance with the same habits.
- **best_change**: the single change that helps the main goal most, why (tied to the customer's habits), and the product's own first step.
- **goals**: every goal with its chance today and with its best change.
- **watch_out**: the risk event most likely to hit this customer, and the change that reduces it.
- **trade_off**: what gets worse (for example, the best futures are less high), when that applies.
- **comparison**: one sentence per scenario.
- **disclaimer**: fixed sentence.

## Use it
```python
from prediction_agent import predict
res = predict(engine_json)   # contract: top of prediction_agent.py, example: example_input.json
res["source"]    # "ai" or "fallback"
res["output"]    # the fields above
res["derived"]   # rule-based facts (best change per goal, differences, main risk) for charts and buttons
res["problems"]  # validator messages when the AI answer was rejected
```
Try it: `python3 prediction_agent.py example_input.json`
A fresh call takes roughly 10 to 25 seconds depending on the model. Call it in the background.

## Setup
Copy `.env.example` to `.env` and put the hIP key after `HIP_API_KEY=`. Never commit `.env`, and never put a real key in `.env.example`.

## Who does what
| Layer | Job |
|---|---|
| Engine (your side) | Simulates the futures, produces every number as a display string |
| Rules (`derive`) | Differences to the baseline, best change per goal, main risk event, trade-off flag. No AI |
| AI | Words only: explains the facts in the customer's own terms |
| Validator (`validate`) | Rejects invented figures, unknown ids, wrong picks, promise or buy/sell wording, missing fields, over-long text |
| Fallback | Deterministic text from the same facts after one failed retry |

## Evaluate
`eval_cases.json` holds 8 synthetic customers (two goals, safety-first goal, unrealistic goal, one change left, nothing left to change).
```
python3 eval_agent.py                                  # current model
python3 eval_agent.py --runs 3 --models "hIP_1.0-Qwen/Qwen3.8-27B,hIP_1.0-Mistral/Mistral-Medium-3.5-128B"
python3 eval_agent.py --show c07                       # print the answers for one case
```
Results on 11 Nov 2026 (8 cases x 3 runs, 6 parallel requests):

| Model | Accepted first try | After retry | Fallback | Avg seconds |
|---|---|---|---|---|
| Mistral-Medium-3.5-128B | 24/24 | 0 | 0 | 20.5 |
| Qwen3.8-27B | 23/24 | 1 | 0 | 10.9 |
| gemma-4-31B-it (1 run) | 8/8 | 0 | 0 | 20.4 |
| Kolibri-1 (1 run) | 2/8 | 6 | 0 | 7.2 |
| Ministral-3-14B (1 run) | 0/8 | 6 | 2 | 22.2 |
| GLM-5.3-Flash (1 run, earlier prompt) | 0/8 | 0 | 8 | 49.6 |

## What your side must provide
One `baseline` scenario, one `change` scenario per habit change the customer has not made yet (with `change` text and, ideally, the product's `first_step` text), an optional `combo`, and for each: `range`, `middle`, `risk_below_today`, `goal_success` per goal and optional `events` with a `chance`. The demo engine (`checkup-demo.html`, seeded Monte Carlo) generated the example and the eval cases; its return and volatility assumptions are illustrative.

## Known limits
- The validator checks figures, ids, picks and wording. It does not check that a sentence states the right direction ("rises" vs "falls"); the eval answers were read by hand.
- Assumptions in the demo engine are not calibrated.
- Use pseudonymous customer data with the gateway.
