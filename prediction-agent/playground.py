#!/usr/bin/env python3
"""
PLAYGROUND  -  a small local web page to try the engine, the Prediction agent and the Action agent.

    python3 playground.py          then open  http://localhost:8790
    PORT=9000 python3 playground.py

Runs only on this computer (binds to 127.0.0.1). The hIP key is read from .env by the agents;
the browser never sees it. Standard library only.
"""
import concurrent.futures as cf
import copy
import json
import os
import sys
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import action_agent as A          # noqa: E402
import engine as E                # noqa: E402
import prediction_agent as P      # noqa: E402

PORT = int(os.environ.get("PORT", "8790"))
MODELS = ["hIP_1.0-Qwen/Qwen3.8-27B", "hIP_1.0-Mistral/Mistral-Medium-3.5-128B", "hIP_1.0-Gemma/gemma-4-31B-it"]

MAX = dict(copy.deepcopy(E.EXAMPLE_CUSTOMER), spending=copy.deepcopy(A.EXAMPLE_SPENDING), purpose="Freedom")
PRESETS = {
    "Max, 26 · heir, 82% in the family company, sells in a crash": MAX,
    "Lena, 29 · young professional, wants a flat in 5 years": {
        "name": "Customer", "age": 29, "profile": "pro", "purpose": "A home of my own",
        "wealth_total": 42000, "cash": 6000, "company_share": 0.0,
        "monthly_income": 4200, "monthly_spending": 3500, "monthly_saving_cash": 300, "monthly_saving_invested": 0,
        "crash_reaction": "hold", "disability_cover": False, "will": False,
        "has_buffer_plan": False, "has_diversification_plan": False, "horizon_years": 15,
        "goals": [{"type": "home", "target": 90000, "years": 5, "priority": 1},
                  {"type": "wealth", "target": 400000, "priority": 2}],
        "spending": {"subscriptions": [{"name": "Streaming bundle", "monthly": 18, "last_used_days": 3},
                                       {"name": "Fitness app", "monthly": 15, "last_used_days": 80},
                                       {"name": "Dating app premium", "monthly": 25, "last_used_days": 120}],
                     "categories": [{"id": "food_delivery", "label": "Food delivery", "monthly": 380, "peer_median": 180}],
                     "planned_purchases": []}},
    "Jonas, 34 · founder, 88% in his start-up, spends more than he earns": {
        "name": "Customer", "age": 34, "profile": "founder", "purpose": "Building something",
        "wealth_total": 1400000, "cash": 8000, "company_share": 0.88,
        "monthly_income": 2500, "monthly_spending": 3400, "monthly_saving_cash": -900, "monthly_saving_invested": 0,
        "crash_reaction": "buy", "disability_cover": False, "will": False,
        "has_buffer_plan": False, "has_diversification_plan": False, "horizon_years": 15,
        "goals": [{"type": "keep", "priority": 1}, {"type": "wealth", "target": 3000000, "priority": 2}],
        "spending": {"subscriptions": [{"name": "Co-working premium", "monthly": 290, "last_used_days": 2},
                                       {"name": "Golf club", "monthly": 180, "last_used_days": 95}],
                     "categories": [{"id": "travel", "label": "Travel", "monthly": 1100, "peer_median": 450}],
                     "planned_purchases": [{"label": "Sports car", "amount": 95000, "in_months": 4}]}},
    "Sara, 45 · doctor, high income, panics in crashes, retires at 60": {
        "name": "Customer", "age": 45, "profile": "pro", "purpose": "Security",
        "wealth_total": 650000, "cash": 40000, "company_share": 0.25,
        "monthly_income": 9500, "monthly_spending": 6800, "monthly_saving_cash": 700, "monthly_saving_invested": 1500,
        "crash_reaction": "sell", "disability_cover": True, "will": False,
        "has_buffer_plan": True, "has_diversification_plan": False, "horizon_years": 15,
        "goals": [{"type": "wealth", "target": 2000000, "priority": 1}, {"type": "keep", "priority": 2}],
        "spending": {"subscriptions": [{"name": "Wine club", "monthly": 120, "last_used_days": 150}],
                     "categories": [{"id": "shopping", "label": "Clothes and shopping", "monthly": 1400, "peer_median": 600}],
                     "planned_purchases": []}},
    "Max, 26 · same, but wants €3m by 41 (honesty test)": dict(copy.deepcopy(MAX), goals=[{"type": "wealth", "target": 3000000, "priority": 1}]),
    "Max, 26 · everything already done": dict(
        copy.deepcopy(MAX), crash_reaction="hold", disability_cover=True, will=True, company_share=0.60, cash=9000,
        monthly_saving_cash=580, monthly_saving_invested=150, has_buffer_plan=True, has_diversification_plan=True,
        monthly_spending=2670,              # after his spending cuts: €2,670 + €730 saved = €3,400 income
        spending={"subscriptions": [], "categories": [], "planned_purchases": []}),
}


def run(customer, model, mode):
    t0 = time.time()
    p_in = E.build_agent_input(customer)
    a_in = A.build_action_input(customer)
    t_engine = round(time.time() - t0, 1)
    rules_only = mode == "fallback"

    def pred():
        t = time.time()
        if rules_only:                      # no LLM call at all: the rule-based text directly
            d = P.derive(p_in)
            r = {"source": "rules", "output": P.fallback(p_in, d), "derived": d, "problems": [], "attempts": 0}
        else:
            r = P.predict(p_in, model=model)
        r["seconds"] = round(time.time() - t, 1)
        return r

    def act():
        t = time.time()
        if not a_in["plan"]:
            r = {"source": "rules", "output": None, "problems": ["no actions apply: nothing left to do"], "attempts": 0}
        elif rules_only:
            r = {"source": "rules", "output": A._assemble(A.fallback_words(a_in), a_in), "problems": [], "attempts": 0}
        else:
            r = A.recommend(a_in, model=model)
        r["seconds"] = round(time.time() - t, 1)
        return r

    with cf.ThreadPoolExecutor(2) as ex:
        fp, fa = ex.submit(pred), ex.submit(act)
        rp, ra = fp.result(), fa.result()
    return {"engine": {"seconds": t_engine, "input": p_in, "customer": customer},
            "action_input": {"plan": a_in["plan"], "not_shown": a_in["not_shown"], "ranking_rule": a_in["ranking_rule"],
                             "quick_wins": a_in["quick_wins"]},
            "intake_warnings": p_in.get("intake_warnings", []),
            "prediction": rp, "action": ra, "mode": mode, "model": model,
            "key_configured": bool(P._cfg()["key"])}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            return self._send(200, PAGE.encode(), "text/html; charset=utf-8")
        if self.path == "/api/presets":
            return self._send(200, {"presets": PRESETS, "models": MODELS, "default_model": MODELS[0],
                                    "key_configured": bool(P._cfg()["key"])})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/run":
            return self._send(404, {"error": "not found"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
            if n > 100000:
                return self._send(413, {"error": "request too large"})
            req = json.loads(self.rfile.read(n) or b"{}")
            model = req.get("model") if req.get("model") in MODELS else MODELS[0]
            out = run(req["customer"], model, "fallback" if req.get("mode") == "fallback" else "ai")
            self._send(200, out)
        except (ValueError, KeyError, TypeError) as e:
            self._send(400, {"error": f"{type(e).__name__}: {e}"})
        except Exception as e:  # keep the playground alive, show the error in the page
            traceback.print_exc()
            self._send(500, {"error": f"{type(e).__name__}: {e}"})

    def log_message(self, fmt, *args):
        if "/api/run" in (args[0] if args else ""):
            sys.stderr.write("  run " + (args[1] if len(args) > 1 else "") + "\n")


PAGE = r"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Agent playground · Financial Health Check-Up</title>
<style>
:root{--bg:#f4f6f9;--card:#fff;--line:#e2e7ee;--ink:#0f1722;--ink2:#465263;--muted:#6f7b8a;--blue:#0018a8;--blue2:#2f55d4;--blueSoft:#eef2ff;
 --teal:#0d8a72;--tealSoft:#e5f5f1;--amber:#a86400;--amberSoft:#fff3df;--red:#b42318;--redSoft:#fdecea}
*{box-sizing:border-box;margin:0;padding:0}
body{font:14px/1.45 system-ui,-apple-system,"Segoe UI",Inter,sans-serif;background:var(--bg);color:var(--ink)}
header{background:var(--card);border-bottom:1px solid var(--line);padding:12px 20px;display:flex;gap:12px;align-items:center;flex-wrap:wrap;position:sticky;top:0;z-index:5}
header h1{font-size:16px;margin-right:auto}header h1 span{color:var(--muted);font-weight:500}
select,input,textarea,button{font:inherit;color:inherit}
select,input{border:1px solid var(--line);border-radius:8px;padding:6px 8px;background:#fff;min-height:34px}
button{border:0;border-radius:8px;padding:8px 14px;cursor:pointer;font-weight:600;min-height:36px}
.run{background:var(--blue);color:#fff}.run:disabled{opacity:.5;cursor:default}
.seg{display:inline-flex;border:1px solid var(--line);border-radius:8px;overflow:hidden}
.seg button{border-radius:0;background:#fff;color:var(--ink2);font-weight:500;padding:6px 10px;min-height:34px}.seg button.on{background:var(--ink);color:#fff}
main{display:grid;grid-template-columns:330px 1fr;gap:16px;padding:16px 20px;align-items:start}
@media(max-width:1000px){main{grid-template-columns:1fr}}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px}
.card h2{font-size:13px;letter-spacing:.06em;text-transform:uppercase;color:var(--blue);margin-bottom:10px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
form .row{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px}
label{display:flex;flex-direction:column;gap:3px;font-size:12px;color:var(--muted);font-weight:600}
label input,label select{color:var(--ink);font-weight:400;width:100%;min-width:0}
form .row>label{min-width:0}
.checks label input{width:auto;min-height:0;flex:none}
.checks{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin:6px 0 10px}.checks label{flex-direction:row;align-items:center;gap:6px;font-weight:500;color:var(--ink2)}
textarea{width:100%;min-height:210px;border:1px solid var(--line);border-radius:8px;padding:8px;font:12px/1.4 ui-monospace,Menlo,monospace}
.hint{font-size:12px;color:var(--muted);margin:4px 0 8px}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:16px}@media(max-width:1300px){.cols{grid-template-columns:1fr}}
.badge{display:inline-flex;gap:4px;align-items:center;font-size:11px;font-weight:700;padding:3px 8px;border-radius:999px;background:var(--bg);color:var(--ink2);text-transform:none;letter-spacing:0}
.badge.ai{background:var(--tealSoft);color:var(--teal)}.badge.fallback{background:var(--amberSoft);color:var(--amber)}.badge.err{background:var(--redSoft);color:var(--red)}
.big{font-size:19px;font-weight:700;line-height:1.3;margin-bottom:6px}
.p{color:var(--ink2);margin-bottom:10px}
.box{border:1px solid var(--line);border-radius:10px;padding:10px 12px;margin-top:10px}
.box b.k{display:block;font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);margin-bottom:3px}
.box.best{border-color:var(--blue2);background:var(--blueSoft)}.box.warn{border-color:#e9c27a;background:var(--amberSoft)}
table{width:100%;border-collapse:collapse;font-size:13px}th{font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);text-align:left;padding:6px 6px 6px 0;border-bottom:1px solid var(--line)}
td{padding:7px 6px 7px 0;border-bottom:1px solid var(--line);vertical-align:top}td.n{font-variant-numeric:tabular-nums;white-space:nowrap}
tr.base td{background:#fafbfc}
.bar{position:relative;height:8px;background:var(--bg);border-radius:4px;min-width:90px;margin-top:6px}.bar i{position:absolute;left:0;top:0;bottom:0;border-radius:4px;background:var(--blue2)}
.bucket{font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);margin:14px 0 6px}
.act{border:1px solid var(--line);border-radius:10px;padding:10px 12px;margin-bottom:8px}
.act .t{font-weight:700;display:flex;justify-content:space-between;gap:8px}.act .g{font-size:12px;color:var(--teal);white-space:nowrap}.act .g.z{color:var(--muted)}
.act .w{margin:4px 0;color:var(--ink)}.act .h{font-size:12px;color:var(--ink2)}.act .v{font-size:12px;color:var(--muted)}
.act .why{font-size:10px;font-weight:700;color:var(--teal);letter-spacing:.05em}
.selves{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:4px}@media(max-width:700px){.selves{grid-template-columns:1fr}}
.self{border-radius:10px;padding:10px 12px;font-size:13px;line-height:1.5}.self .k{display:block;font-size:11px;letter-spacing:.06em;text-transform:uppercase;margin-bottom:4px}
.self.same{background:#f3f4f6;color:var(--ink2)}.self.same .k{color:var(--muted)}.self.chg{background:var(--tealSoft);color:var(--ink)}.self.chg .k{color:var(--teal)}
.wim{margin:4px 0 0 18px}.wim li{margin:3px 0}
.meet{background:var(--blueSoft);border-radius:10px;padding:10px 12px;margin-top:6px}
.prob{font-size:12px;color:var(--amber);margin-top:6px}
.empty{color:var(--muted);padding:30px 0;text-align:center}
.spin{display:inline-block;width:14px;height:14px;border:2px solid var(--line);border-top-color:var(--blue);border-radius:50%;animation:s .8s linear infinite;vertical-align:-2px}@keyframes s{to{transform:rotate(360deg)}}
details{margin-top:12px}summary{cursor:pointer;color:var(--muted);font-size:12px}pre{font-size:11px;background:var(--bg);padding:10px;border-radius:8px;overflow:auto;max-height:420px;margin-top:6px}
.foot{font-size:11px;color:var(--muted);margin-top:10px}
.ai-mark{font-size:10px;font-weight:700;background:var(--tealSoft);color:var(--teal);border-radius:4px;padding:1px 5px;margin-left:4px;vertical-align:1px}
.legend{font-size:12px;color:var(--muted);margin:-4px 0 10px}
</style></head><body>
<header>
 <h1>Agent playground <span>· Prediction &amp; Action agents</span></h1>
 <label style="flex-direction:row;align-items:center;gap:6px">Customer <select id="preset"></select></label>
 <label style="flex-direction:row;align-items:center;gap:6px">Model <select id="model"></select></label>
 <div class="seg" id="mode"><button type="button" data-m="ai" class="on">Live AI</button><button type="button" data-m="fallback">Rules only (no AI)</button></div>
 <button class="run" id="run" type="button">Run both agents</button>
</header>
<main>
 <section class="card">
  <h2>Customer intake</h2>
  <form id="f" onsubmit="return false">
   <div class="row"><label>Age<input name="age" type="number"></label><label>Wealth €<input name="wealth_total" type="number" step="1000"></label></div>
   <div class="row"><label>Cash €<input name="cash" type="number" step="100"></label><label>Company share %<input name="company_share" type="number" step="1"></label></div>
   <div class="row"><label>Income €/month<input name="monthly_income" type="number" step="50"></label><label>Spending €/month<input name="monthly_spending" type="number" step="50"></label></div>
   <div class="row"><label>Saves to cash €/m<input name="monthly_saving_cash" type="number" step="10"></label><label>Saves invested €/m<input name="monthly_saving_invested" type="number" step="10"></label></div>
   <div class="row"><label>Crash test reaction<select name="crash_reaction"><option value="sell">Sold everything</option><option value="hold">Held</option><option value="buy">Bought more</option></select></label><label>Profile<select name="profile"><option value="heir">Heir</option><option value="founder">Founder</option><option value="pro">Young professional</option></select></label></div>
   <div class="checks">
    <label><input type="checkbox" name="disability_cover"> Disability cover</label><label><input type="checkbox" name="will"> Has a will</label>
    <label><input type="checkbox" name="has_buffer_plan"> Buffer plan running</label><label><input type="checkbox" name="has_diversification_plan"> Diversification agreed</label>
   </div>
   <b class="hint" style="display:block;color:var(--ink2)">Goals</b>
   <div class="row"><label>Horizon (years)<input name="horizon_years" type="number" min="3" max="30"></label><label>Money is for<input name="purpose"></label></div>
   <div class="row"><label>Goal 1<select name="g1t"><option value="wealth">Reach wealth</option><option value="home">Save for a home</option><option value="keep">Do not end below today</option></select></label><label>Target € · in years (home)<span style="display:flex;gap:4px"><input name="g1v" type="number" step="5000"><input name="g1y" type="number" min="1" style="width:56px" title="years (home goal)"></span></label></div>
   <div class="row"><label>Goal 2<select name="g2t"><option value="">None</option><option value="wealth">Reach wealth</option><option value="home">Save for a home</option><option value="keep">Do not end below today</option></select></label><label>Target € · in years (home)<span style="display:flex;gap:4px"><input name="g2v" type="number" step="5000"><input name="g2y" type="number" min="1" style="width:56px" title="years (home goal)"></span></label></div>
   <b class="hint" style="display:block;color:var(--ink2)">Spending (from transactions)</b>
   <p class="hint">Subscriptions with days since last use, categories with the peer median, planned purchases.</p>
   <textarea name="spending" spellcheck="false"></textarea>
   <p class="foot" id="keyinfo"></p>
  </form>
 </section>
 <section>
  <div class="card" id="engine"><h2>Engine · simulated futures</h2><p class="empty">Pick a customer and press <b>Run both agents</b>.</p></div>
  <div class="cols" style="margin-top:16px">
   <div class="card" id="pred"><h2>Prediction agent</h2><p class="empty">What can happen if you keep your habits, and if you change them.</p></div>
   <div class="card" id="act"><h2>Action agent</h2><p class="empty">What to do next, in order.</p></div>
  </div>
 </section>
</main>
<script>
const $=s=>document.querySelector(s),esc=s=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
let PRESETS={},MODE='ai',CUR={};
const F=()=>$('#f').elements;
function fill(c){CUR=JSON.parse(JSON.stringify(c));const f=F();
 ['age','wealth_total','cash','monthly_income','monthly_spending','monthly_saving_cash','monthly_saving_invested'].forEach(k=>f[k].value=c[k]);
 f.company_share.value=Math.round(c.company_share*100);f.crash_reaction.value=c.crash_reaction;f.profile.value=c.profile||'heir';
 ['disability_cover','will','has_buffer_plan','has_diversification_plan'].forEach(k=>f[k].checked=!!c[k]);
 const g=[...c.goals].sort((a,b)=>a.priority-b.priority);
 f.g1t.value=g[0].type;f.g1v.value=g[0].target||'';f.g1y.value=g[0].years||'';f.g2t.value=g[1]?g[1].type:'';f.g2v.value=g[1]&&g[1].target||'';f.g2y.value=g[1]&&g[1].years||'';
 f.horizon_years.value=c.horizon_years||15;f.purpose.value=c.purpose||'';
 f.spending.value=JSON.stringify(c.spending||{subscriptions:[],categories:[],planned_purchases:[]},null,1);}
function read(){const f=F(),n=k=>Number(f[k].value);
 let spending;try{spending=JSON.parse(f.spending.value||'{}')}catch(e){throw new Error('Spending is not valid JSON: '+e.message)}
 const goals=[{type:f.g1t.value,target:n('g1v'),years:n('g1y'),priority:1}];if(f.g2t.value)goals.push({type:f.g2t.value,target:n('g2v'),years:n('g2y'),priority:2});
 goals.forEach(g=>{if(g.type!=='home')delete g.years;else if(!g.years)throw new Error('Give the home goal a number of years');if(g.type==='keep')delete g.target;else if(!g.target)throw new Error('Give each wealth or home goal a target in €')});
 return {...CUR,name:'Customer',age:n('age'),profile:f.profile.value,horizon_years:n('horizon_years'),purpose:f.purpose.value,wealth_total:n('wealth_total'),cash:n('cash'),company_share:n('company_share')/100,
  monthly_income:n('monthly_income'),monthly_spending:n('monthly_spending'),monthly_saving_cash:n('monthly_saving_cash'),monthly_saving_invested:n('monthly_saving_invested'),
  crash_reaction:f.crash_reaction.value,disability_cover:f.disability_cover.checked,will:f.will.checked,has_buffer_plan:f.has_buffer_plan.checked,
  has_diversification_plan:f.has_diversification_plan.checked,goals,spending};}
function badge(r){if(!r)return'';const s=r.source,n=Math.max(0,(r.attempts||1)-1),nf=Object.keys((r.validation||{}).replaced_fields||{}).length;
 const t={rules:['','Rules only'],ai:['ai',n?'Live AI · fixed after 1 retry':'Live AI'],ai_partial:['fallback',`Live AI · ${nf} part${nf===1?'':'s'} replaced by rules`],
  fallback:['fallback',`Fallback · AI failed after ${n} retr${n===1?'y':'ies'}`]}[s]||['',esc(s)];
 return `<span class="badge ${t[0]}">${t[1]}</span><span class="badge">${r.seconds}s</span>`;}
function probs(r){if(!r)return'';const v=r.validation||{},att=(v.attempts||[]).filter(a=>Object.keys(a.violations||{}).length);
 if(r.source==='rules')return'';
 let h='';if(att.length)h+=`<p class="prob">Guardrail: ${att.length} answer${att.length>1?'s':''} rejected (${esc(att.map(a=>Object.entries(a.violations).map(([k,m])=>FIELD(k)+': '+m.join('; ')).join(' | ')).join(' → '))}).</p>`;
 const rep=Object.keys(v.replaced_fields||{});if(rep.length)h+=`<p class="prob">Replaced by rule-based text: ${esc(rep.map(FIELD).join(', '))}.</p>`;return h;}
const FIELD=k=>k==='*'?'whole answer':k.replace(/_/g,' ').replace(/\[(\d+)\]/,(m,i)=>' #'+(+i+1));
function renderEngine(d){const inp=d.engine.input,g=[...inp.customer.goals].sort((a,b)=>a.priority-b.priority),m=g[0].id;
 const rows=inp.scenarios.map(s=>{const r=s.results,ev=id=>(r.events.find(e=>e.id===id)||{}).chance||'–',gp=parseInt(r.goal_success[m]);
  return `<tr class="${s.kind==='baseline'?'base':''}"><td><b>${esc(s.label)}</b><div class="hint" style="margin:0">${esc(s.kind)}</div></td><td class="n">${esc(r.range)}</td><td class="n">${esc(r.middle)}</td>
  <td class="n">${esc(r.goal_success[m])}<div class="bar" role="img" aria-label="${esc(r.goal_success[m])}"><i style="width:${gp}%"></i></div></td><td class="n">${esc(r.risk_below_today)}</td>
  <td class="n">${esc(ev('panic_sale'))}</td><td class="n">${esc(ev('income_gap'))}</td><td class="n">${esc(((r.events.find(e=>e.id==='company_shock')||{}).typical_hit||'–').split(' ')[0])}</td></tr>`;}).join('');
 $('#engine').innerHTML=`<h2>Engine · simulated futures <span class="badge">${inp.paths.toLocaleString('en')} futures · ${inp.horizon_years} years · ${d.engine.seconds}s</span></h2>
 <p class="legend">Main goal: <b>${esc(g[0].label)}</b>. These numbers come from the simulation, not from the AI. Both agents may only quote them.</p>
 <div style="overflow:auto"><table><thead><tr><th>Scenario</th><th>Range (weak – strong)</th><th>Middle</th><th>Goal chance</th><th>Ends below today</th><th>Panic sale</th><th>Year w/o income</th><th>Company shock hit</th></tr></thead><tbody>${rows}</tbody></table></div>`;}
function renderPred(r,inp){const el=$('#pred'),lab=id=>esc((inp.scenarios.find(s=>s.id===id)||{}).label||id);if(!r||!r.output){el.innerHTML='<h2>Prediction agent</h2><p class="empty">No result.</p>';return}
 const o=r.output,ai=r.source==='ai'?'<span class="ai-mark">AI</span>':'';
 el.innerHTML=`<h2>Prediction agent ${badge(r)}</h2><div class="big">${esc(o.headline)}${ai}</div><p class="p">${esc(o.if_nothing_changes)}</p>
 ${o.future_selves?`<div class="selves"><div class="self same"><b class="k">Future you · same habits</b>${esc(o.future_selves.same_habits)}</div><div class="self chg"><b class="k">Future you · with changes</b>${esc(o.future_selves.with_changes)}</div></div>`:''}
 ${o.what_it_means&&o.what_it_means.length?`<div class="box"><b class="k">What it means for you</b><ul class="wim">${o.what_it_means.map(w=>`<li>${esc(w)}</li>`).join('')}</ul></div>`:''}
 ${o.best_change?`<div class="box best"><b class="k">Best single change</b><b>${lab(o.best_change.scenario_id)}</b><div style="margin-top:3px">${esc(o.best_change.why)}</div><div class="h" style="margin-top:6px;font-size:12px;color:var(--ink2)">First step: ${esc(o.best_change.first_step)}</div></div>`:'<div class="box"><b class="k">Best single change</b>Nothing left to change.</div>'}
 ${o.watch_out?`<div class="box warn"><b class="k">Watch out</b>${esc(o.watch_out.sentence)}</div>`:''}
 ${o.trade_off?`<div class="box"><b class="k">Trade-off</b>${esc(o.trade_off)}</div>`:''}
 <div class="box"><b class="k">Your goals</b>${o.goals.map(g=>`<div style="margin-top:4px">${esc(g.sentence)}</div>`).join('')}</div>
 ${o.comparison.length?`<div class="box"><b class="k">Each change compared with same habits</b><table><tbody>${o.comparison.map(c=>`<tr><td style="width:32%"><b>${lab(c.scenario_id)}</b></td><td>${esc(c.what_happens)}</td></tr>`).join('')}</tbody></table></div>`:''}
 ${probs(r)}<p class="foot">${esc(o.disclaimer)}</p>
 <details><summary>Rule-based facts the AI was given (derived)</summary><pre>${esc(JSON.stringify(r.derived,null,1))}</pre></details>
 <details><summary>Raw agent output</summary><pre>${esc(JSON.stringify({output:o,validation:r.validation||null},null,1))}</pre></details>`;}
function renderAct(r,ai_in){const el=$('#act');if(!r||!r.output){el.innerHTML=`<h2>Action agent ${badge(r)}</h2><p class="empty">${esc((r&&r.problems||['No result'])[0])}</p>`;return}
 const o=r.output,names={this_week:'This week · you can do it alone',this_month:'This month',with_your_advisor:'With your advisor'};let cur='',h='';
 o.actions.forEach(a=>{if(a.bucket!==cur){cur=a.bucket;h+=`<div class="bucket">${names[cur]}</div>`;}
  const el=a.impact.effect_label||'',plan=(ai_in.plan.find(p=>p.id===a.action_id)||{});
  h+=`<div class="act"><div class="t"><span>${esc(a.title)}</span><span class="g ${/^goal|^keeps/.test(el)?'':'z'}">${esc(el)}</span></div>
  <div class="w"><span class="why">WHY${r.source==='ai'?' · AI':''}</span> ${esc(a.why)}</div><div class="h"><b>How:</b> ${esc(a.how)}</div><div class="v">Proof: ${esc(a.verified_by)} · Effort: ${esc(a.effort)} · rank points ${esc(plan.priority_points)}</div></div>`;});
 el.innerHTML=`<h2>Action agent ${badge(r)}</h2><div class="big">${esc(o.intro)}${r.source==='ai'?'<span class="ai-mark">AI</span>':''}</div>${h}
 ${o.advisor_meeting?`<div class="meet"><b>One advisor meeting:</b> ${esc(o.advisor_meeting.sentence)}</div>`:''}
 ${ai_in.not_shown.length?`<p class="foot">Also applies but not shown (group full): ${esc(ai_in.not_shown.map(x=>x.title).join('; '))}</p>`:''}
 ${probs(r)}<p class="foot">${esc(o.disclaimer)}</p><p class="foot">Ranking: ${esc(ai_in.ranking_rule)}</p>
 <details><summary>Raw agent output</summary><pre>${esc(JSON.stringify({output:o,validation:r.validation||null},null,1))}</pre></details>`;}
function render(d){renderEngine(d);if(d.intake_warnings&&d.intake_warnings.length)$('#engine').insertAdjacentHTML('beforeend',`<p class="prob">Intake check: ${esc(d.intake_warnings.join(' '))}</p>`);renderPred(d.prediction,d.engine.input);renderAct(d.action,d.action_input);}
async function go(){let c;try{c=read()}catch(e){alertBox(e.message);return}
 const b=$('#run');b.disabled=true;b.innerHTML='<span class="spin"></span> Running…';
 const wait=MODE==='ai'?' · live AI usually takes 5–25 s':'';
 ['#pred','#act'].forEach(s=>$(s).innerHTML=`<h2>${s==='#pred'?'Prediction':'Action'} agent</h2><p class="empty"><span class="spin"></span> Working${wait}</p>`);
 $('#engine').innerHTML='<h2>Engine · simulated futures</h2><p class="empty"><span class="spin"></span> Simulating 2,000 futures per scenario…</p>';
 try{const r=await fetch('/api/run',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({customer:c,model:$('#model').value,mode:MODE})});
  const d=await r.json();if(!r.ok)throw new Error(d.error||r.status);render(d);}catch(e){alertBox(e.message)}finally{b.disabled=false;b.textContent='Run both agents';}}
function alertBox(m){$('#engine').innerHTML=`<h2>Engine · simulated futures</h2><p class="prob" style="font-size:14px">${esc(m)}</p>`;}
document.querySelectorAll('#mode button').forEach(b=>b.onclick=()=>{MODE=b.dataset.m;document.querySelectorAll('#mode button').forEach(x=>x.classList.toggle('on',x===b));});
$('#run').onclick=go;$('#preset').onchange=()=>fill(PRESETS[$('#preset').value]);
fetch('/api/presets').then(r=>r.json()).then(d=>{PRESETS=d.presets;
 $('#preset').innerHTML=Object.keys(d.presets).map(k=>`<option>${esc(k)}</option>`).join('');
 $('#model').innerHTML=d.models.map(m=>`<option value="${esc(m)}">${esc(m.split('/').pop())}</option>`).join('');
 fill(PRESETS[Object.keys(PRESETS)[0]]);
 $('#keyinfo').textContent=d.key_configured?'hIP key found in .env (stays on this computer).':'No hIP key found: live AI falls back to rules-only text. Put HIP_API_KEY in .env.';
 if(window.__DEMO__)render(window.__DEMO__);});
</script></body></html>"""


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Agent playground: http://localhost:{PORT}   (key {'found' if P._cfg()['key'] else 'MISSING, rules-only mode'}; Ctrl+C to stop)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
