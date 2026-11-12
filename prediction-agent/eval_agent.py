#!/usr/bin/env python3
"""Evaluate the Prediction agent on eval_cases.json.
Usage: python3 eval_agent.py [--models a,b,c] [--runs N] [--show CASE_ID] [--save out.json]
Reports per model: answers accepted on the first attempt, after the retry, fallbacks, and latency.
Each run uses a unique customer name so the gateway cannot answer from its cache."""
import concurrent.futures as cf, json, os, random, sys, time
import prediction_agent as a

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
opt = lambda k, d=None: args[args.index(k) + 1] if k in args else d
models = (opt("--models") or a._cfg()["model"]).split(",")
runs = int(opt("--runs", "1"))
cases = json.load(open(os.path.join(HERE, "eval_cases.json"), encoding="utf8"))

def one(job):
    model, c = job
    data = json.loads(json.dumps(c["input"]))
    data["customer"]["name"] = "Customer-%06d" % random.randrange(10**6)
    first = []
    def call(cfg, msg):
        t = a._call_model(cfg, msg)
        if not first:
            try: first.append(a.validate(a._parse_json(t), data))
            except Exception as e: first.append(["unparseable: " + str(e)[:60]])
        return t
    t0 = time.time()
    try: r = a.predict(data, call=call, model=model)
    except Exception as e: r = {"source": "error", "attempts": 0, "problems": [str(e)[:120]], "output": None}
    return {"model": model, "case": c["case"], "note": c["note"], "source": r["source"], "attempts": r["attempts"],
            "first_problems": first[0] if first else r["problems"], "problems": r["problems"],
            "seconds": round(time.time() - t0, 1), "output": r["output"]}

jobs = [(m, c) for m in models for c in cases] * runs
with cf.ThreadPoolExecutor(6) as ex:
    res = list(ex.map(one, jobs))
print(f"{'model':42} {'1st try':>8} {'retry':>6} {'fallback':>9} {'avg s':>6} {'max s':>6}")
for m in models:
    rs = [r for r in res if r["model"] == m]
    n = len(rs); f1 = sum(r["source"] == "ai" and r["attempts"] == 1 for r in rs)
    f2 = sum(r["source"] == "ai" and r["attempts"] == 2 for r in rs); fb = n - f1 - f2
    sec = [r["seconds"] for r in rs]
    print(f"{m:42} {f1:>5}/{n:<2} {f2:>6} {fb:>9} {sum(sec)/n:>6.1f} {max(sec):>6.1f}")
    seen = {}
    for r in rs:
        for pr in r["first_problems"]: seen[pr[:90]] = seen.get(pr[:90], 0) + 1
    for k, v in sorted(seen.items(), key=lambda x: -x[1])[:4]: print(f"      {v}x {k}")
if opt("--show"):
    for r in res:
        if r["case"] == opt("--show") and r["source"] == "ai":
            print("\n###", r["model"], r["case"], r["note"]); print(json.dumps(r["output"], indent=1, ensure_ascii=False))
if opt("--save"):
    json.dump(res, open(opt("--save"), "w", encoding="utf8"), indent=1, ensure_ascii=False)
