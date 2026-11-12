#!/usr/bin/env python3
"""
FinPulse bridge: serves the team's prediction-agent folder over HTTP for the Java backend.
Standard library only. Put this file in the prediction-agent folder (next to engine.py) and run:

    python kairos_server.py --agent-dir ../prediction-agent --projects-dir ../projects-section
    python kairos_server.py --port 8090 --agent-dir ../prediction-agent --projects-dir ../projects-section

Endpoints (all JSON):
    GET  /health       -> {"ok", "live_ai", "engine_version", "prediction_agent", "action_agent"}
    POST /assessment   body = customer intake  -> everything below in one call (agents run in parallel)
    POST /engine       body = customer intake  -> engine.build_agent_input()
    POST /chart        body = customer intake  -> fan chart (p10/p50/p90 per year), same habits vs full plan
    POST /predict      body = agent input, or {"intake": ...}  -> prediction_agent.predict()
    POST /actions      body = customer intake (with "spending") -> action_agent.recommend()

/assessment returns {intake, engine, chart, prediction, actions, kairos}; "kairos" is the exact shape the
projects section reads (intake + engine summary + prediction_agent + action_agent).
The OPENAI_API_KEY stays in backend/.env. Without a key both agents use their rule-based text.
"""
import argparse
import json
import time
import os
import sys
import subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=8090)
parser.add_argument("--agent-dir", default=os.path.dirname(os.path.abspath(__file__)))
parser.add_argument("--env-file", default=str(Path(__file__).resolve().parents[1] / ".env"))
parser.add_argument("--projects-dir", required=True)
args = parser.parse_args()
PROJECTS_DIR = str(Path(args.projects_dir).resolve())
RUNNER = str(Path(__file__).with_name("projects_runner.cjs").resolve())
# One backend-owned secret; never load a browser key or a legacy agent key.
config = {}
try:
    for line in Path(args.env_file).read_text().splitlines():
        if line.strip() and not line.lstrip().startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            config[key.strip()] = value.strip().strip("\"'")
except FileNotFoundError:
    pass
for key, fallback in (("OPENAI_API_KEY", ""), ("OPENAI_MODEL", "gpt-4.1-mini"),
                      ("OPENAI_BASE_URL", "https://api.openai.com/v1")):
    config[key] = os.environ.get(key, config.get(key, fallback))
os.environ["HIP_API_KEY"] = config["OPENAI_API_KEY"]
os.environ["HIP_MODEL"] = config["OPENAI_MODEL"]
os.environ["HIP_BASE_URL"] = config["OPENAI_BASE_URL"]
AGENT_DIR = os.path.abspath(args.agent_dir)
sys.path.insert(0, AGENT_DIR)
os.chdir(AGENT_DIR)                      # the agents read .env and write guardrail.log here
import engine as E                       # noqa: E402
import prediction_agent as P             # noqa: E402
import action_agent as A                 # noqa: E402

POOL = ThreadPoolExecutor(max_workers=8)


def engine_summary(agent_input):
    """Compact engine view in the format of projects-section/input.txt."""
    goals = sorted(agent_input["customer"]["goals"], key=lambda g: g.get("priority", 99))
    main = goals[0] if goals else None
    out = []
    for s in agent_input["scenarios"]:
        r = s["results"]
        row = {"id": s["id"], "label": s["label"], "range": r["range"], "middle": r["middle"],
               "goal_success": r["goal_success"].get(main["id"]) if main else None,
               "risk_below_today": r["risk_below_today"]}
        ev = {e["id"]: e["chance"] + (f" (hit {e['typical_hit'].split(' ')[0]})" if e.get("typical_hit") else "")
              for e in r.get("events") or []}
        if ev:
            row["events"] = ev
        out.append(row)
    return {"paths": agent_input["paths"], "horizon": agent_input["horizon"],
            "main_goal": main["label"] if main else None, "scenarios": out}


def chart(intake):
    """Fan chart (p10 / p50 / p90 per year): same habits vs all open changes together."""
    a = E.assumptions_for(intake)
    base = E._world(intake)
    full = base
    for lv in E.open_levers(intake, a):
        full = E.apply_lever(full, lv)
    now, plan = E.simulate(intake, base, a), E.simulate(intake, full, a)
    pick = lambda o: {"p10": o["p10"], "p50": o["p50"], "p90": o["p90"], "riskBelowToday": o["below"]}
    # one path per single change too, so the chart follows the scenario the customer picks
    by = {"baseline": pick(now), "full_plan": pick(plan)}
    for lv in E.open_levers(intake, a):
        by[lv] = pick(E.simulate(intake, E.apply_lever(base, lv), a))
    return {"startAge": intake["age"], "years": a["years"], "wealthNow": intake["wealth_total"],
            "todayPath": pick(now), "fullPlan": pick(plan), "byScenario": by}


def _timed(fn, *a):
    t = time.perf_counter()
    r = fn(*a)
    if isinstance(r, dict):
        r["seconds"] = round(time.perf_counter() - t, 2)
    return r


def assessment(intake):
    t0 = time.perf_counter()
    agent_input = E.build_agent_input(intake)
    engine_s = round(time.perf_counter() - t0, 2)
    f_pred = POOL.submit(_timed, P.predict, agent_input)
    f_act = POOL.submit(_timed, lambda: A.recommend(A.build_action_input(intake))) if intake.get("spending") is not None else None
    pred = f_pred.result()
    acts = f_act.result() if f_act else None
    agent_input = {**agent_input, "timings": {"engine_seconds": engine_s, "total_seconds": round(time.perf_counter() - t0, 2),
                                              "prediction_seconds": pred.get("seconds"),
                                              "action_seconds": acts.get("seconds") if acts else None}}
    kairos = {"intake": intake, "engine": engine_summary(agent_input),
              "prediction_agent": {"source": pred["source"], **pred["output"]},
              "action_agent": ({"source": acts["source"], **acts["output"]} if acts else None)}
    return {"intake": intake, "engine": agent_input, "chart": chart(intake), "prediction": pred, "actions": acts, "kairos": kairos}


def run_projects(data):
    result = subprocess.run(["node", RUNNER, PROJECTS_DIR], input=json.dumps(data),
                            text=True, encoding="utf-8", capture_output=True, timeout=15)
    if result.returncode:
        raise ValueError("Project inputs or planner response could not be validated")
    return json.loads(result.stdout)


def project_plan(data):
    prepared = run_projects(data)
    fallback = {"source": "rules", "plan": None, "affordability": prepared["facts"]["affordability"]}
    if not P._cfg()["key"]:
        return {**fallback, "message": "Set OPENAI_API_KEY in backend/.env to enable project estimates."}
    try:
        reply = P._call_model(P._cfg(), json.dumps(prepared["facts"]), prepared["system"])
        result = run_projects({**data, "reply": reply})
        return {"source": "ai", **result}
    except Exception:
        return {**fallback, "message": "AI estimate unavailable; affordability limits are still available."}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n).decode("utf-8"))

    def do_GET(self):
        if self.path.rstrip("/") == "/health":
            return self._send(200, {"ok": True, "live_ai": bool(P._cfg()["key"]), "provider": "openai", "model": P._cfg()["model"], "projects": True, "engine_version": E.ENGINE_VERSION,
                                    "prediction_agent": getattr(P, "AGENT_VERSION", "?"), "action_agent": A.AGENT_VERSION})
        self._send(404, {"error": "see the docstring for endpoints"})

    def do_POST(self):
        path = self.path.rstrip("/")
        try:
            data = self._body()
            if path == "/projects":
                return self._send(200, project_plan(data))
            if path == "/assessment":
                return self._send(200, assessment(data))
            if path == "/chart":
                return self._send(200, chart(data))
            if path == "/engine":
                return self._send(200, E.build_agent_input(data))
            if path == "/predict":
                agent_input = E.build_agent_input(data["intake"]) if "intake" in data else data
                problems = P.check_input(agent_input)
                if problems:
                    return self._send(400, {"error": "invalid engine input", "problems": problems})
                return self._send(200, P.predict(agent_input))
            if path == "/actions":
                return self._send(200, A.recommend(A.build_action_input(data)))
            self._send(404, {"error": "unknown endpoint"})
        except ValueError as e:
            self._send(400, {"error": str(e)})
        except Exception as e:                       # keep the bridge alive whatever happens
            self._send(500, {"error": f"{type(e).__name__}: {e}"})

    def log_message(self, fmt, *a):
        sys.stderr.write("kairos_server: " + (fmt % a) + "\n")


if __name__ == "__main__":
    live = bool(P._cfg()["key"])
    print(f"FinPulse bridge on http://localhost:{args.port}  (engine {E.ENGINE_VERSION}, live AI: {'yes' if live else 'no, rule-based text'})")
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
