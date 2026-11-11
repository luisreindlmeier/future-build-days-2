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

## Files
| File | What it is |
|---|---|
| `engine.py` | Simulation engine: customer intake -> agent input (seeded Monte Carlo, 2,000 futures, 15 years) |
| `prediction_agent.py` | The agent: rules, AI wording, validator, fallback |
| `action_agent.py` | Action agent: ranked action plan (spending, saving, advisor topics, will) with engine-computed impact |
| `test_action_agent.py` | Action agent tests: triggers, grouping, advisor routing, validator (no network) |
| `test_engine.py` | Engine tests, incl. exact parity with the demo's JavaScript engine (no network) |
| `eval_agent.py`, `eval_cases.json` | Live model evaluation on 8 synthetic customers |
| `example_input.json` | Example agent input produced by the engine |

## Guardrails (v2.2)
- `guardrails.py` checks every AI text field before it is shown: each EUR amount (by value, so €1.07m = €1,070k), %, point difference, duration and plain number must appear in the facts for that part of the answer (customer + same habits + the scenario or action the field is about); no forbidden wording (eliminated/removed/gone only for a risk at 0% and with "in the simulation"; no guaranteed, safe, certain, peace of mind, legacy, Start today ...); no raw ids; no buy/sell instructions.
- On a violation the model gets one retry with the list of violations. If it fails again, only the failing fields are replaced by rule-based text (`source: ai_partial`); the record is in `validation` and shown under "Raw agent output" in the playground. Every event is logged to the console and `guardrail.log`.
- Facts are noise-filtered: differences under 2 points (2,000 paths, common random numbers across scenarios) are "no clear change". Each scenario has `risks_remaining` (removed / reduced / unchanged / increased); every life fact and impact carries a `scenario_id`.
- Action agent: "freed" money (spending cuts, cancellations) is kept apart from "set aside" money (buffer, investment plan).
- Engine 1.1: the buffer stops at 3 months of spending (`buffer_months`), then the monthly amount goes to investments; panic sellers stay in cash for 2 years and miss a modelled rebound (`panic_out_years`, `rebound`; see the comments in `ASSUMPTIONS`); intake plausibility warnings (`intake_warnings`). `LEGACY_ASSUMPTIONS` reproduces the demo engine for the parity test.
- `test_all_customers.py` runs every sample customer through rules-only and live AI and asserts no raw ids, no forbidden words, traceable numbers and correct freed money (`SKIP_AI=1` for offline).

## Human impact (v2.1)
Both agents now write for one person and show what the money means in their life, while every figure stays verified:
- **Life facts are computed by the rules, not the AI**: "your cash would cover 1.1 months of your bills", "€154k more at 41, which is 4.6 years of your current spending", "€4,800 a year, €72k set aside over 15 years", "€24k by your home goal in 5 years".
- **The Prediction agent adds two "future you" scenes** (same habits vs. with changes) and "what it means" sentences; the **Action agent** turns each step into a concrete life image linked to the person's purpose.
- The prompts give the model a creative brief (profile, purpose, varied language, temperature 0.6), with hard limits: no invented figures or durations, no invented family or life events, no outcome stated as certain ("within reach", never "you own a home"). The validator checks figures, durations and certainty phrases; on failure the model is asked to repair once, then the fallback text is used.
- Engine intake supports `profile` (heir / founder / pro), `purpose`, `horizon_years`, a `home` goal and income-scaled saving steps; a customer who spends more than they earn gets "Spend no more than you earn" first.

## Action agent
Turns the customer's data into a plan in three groups: **this week** (quick wins you can do alone: start a buffer, cancel unused subscriptions, set a limit for a category far above people like you, put a big purchase on hold), **this month** (will), and **with your advisor** (diversification plan, investment plan, crash rules, income protection), bundled into one meeting.
Rules decide which actions apply, their order, titles, steps, verification and effect on the main goal (re-simulated by the engine). The AI writes only the intro, one personal "why" per action and the meeting sentence. It never gives buy/sell instructions for securities or names products: investment topics always go to the advisor.
```python
from engine import EXAMPLE_CUSTOMER
from action_agent import build_action_input, recommend, EXAMPLE_SPENDING
plan = recommend(build_action_input(dict(EXAMPLE_CUSTOMER, spending=EXAMPLE_SPENDING)))
```
The spending intake (subscriptions with last use, categories with a peer median, planned purchases) is documented at the top of `action_agent.py`. Live test 11 Nov 2026, 3 customers x 3 runs: Mistral Medium 9/9 first try (11 s), Qwen 27B 9/9 (6 s).

## Full pipeline
```python
from engine import build_agent_input, EXAMPLE_CUSTOMER
from prediction_agent import predict
res = predict(build_agent_input(EXAMPLE_CUSTOMER))   # intake -> engine (~1 s) -> agent (~10-25 s)
```
The intake format is `EXAMPLE_CUSTOMER` at the top of `engine.py`. The engine's `ASSUMPTIONS` (returns, volatility, chance of income loss) are illustrative demo values: replace them with the bank's own figures before production use.

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
