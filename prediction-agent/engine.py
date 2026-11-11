#!/usr/bin/env python3
"""
SIMULATION ENGINE  -  Financial Health Check-Up, input builder for the Prediction agent

Turns a customer's intake data (position, habits, goals) into the agent's input
(schema_version 2): a "same habits" baseline, one scenario per habit change the
customer has not made yet, and "all changes together". Every number the agent
may quote is produced here, as a display string.

How it works
    Seeded Monte Carlo: PATHS possible futures, simulated year by year for YEARS years.
    Three pots: family company shares, invested money, cash. Each year the company and
    the broad market get a random return (log-normal, partly correlated).
    Behaviour that is modelled:
      - panic seller: after a market fall of 15% or more, sits in cash for a year
        and misses the rebound
      - a year without income (small chance each year): without cover the full
        spending gap comes out of savings, with cover 60% of income is replaced
      - saving: monthly amounts into cash and investments; a full buffer
        (6 months of spending) spills over into investments
      - diversification plan: company share glides down 11 points a year to 60%
    Every scenario runs on the SAME random draws (same seed), so differences between
    scenarios come from the customer's choices, not from luck.

What it is not
    The ASSUMPTIONS are illustrative demo values, not calibrated capital-market
    assumptions. No tax, costs, inflation or salary growth. Replace ASSUMPTIONS with
    the bank's own figures before production use.

This is a line-by-line port of the engine in checkup-demo.html; test_engine.py
checks that both give identical results. Python 3.9+, standard library only.

Use
    from engine import build_agent_input
    from prediction_agent import predict
    agent_input = build_agent_input(customer)        # customer: see EXAMPLE_CUSTOMER
    result = predict(agent_input)

    python3 engine.py                  # prints the agent input for EXAMPLE_CUSTOMER
    python3 engine.py customer.json    # same for your own intake file
"""
import json
import math
import sys

ENGINE_VERSION = "1.0"

ASSUMPTIONS = {
    "years": 15, "paths": 2000, "seed": 260841,
    "company": {"mu": 0.07, "sd": 0.30},     # single family company: average return, yearly swings
    "market": {"mu": 0.06, "sd": 0.15},      # broad diversified market
    "rho": 0.3,                              # how strongly company and market move together
    "cash_rate": 0.015,
    "p_income_loss": 0.004,                  # chance per year of a year without income
    "panic_at": -0.15,                       # market fall that triggers a panic sale
    "glide": 0.11, "floor": 0.60,            # diversification: points per year, target share
    "buffer_months": 6,                      # cash above this many months of spending is invested
    "cover_replaces": 0.6,                   # share of income paid by disability cover
}

# Intake for one customer. Amounts in EUR per month unless stated.
EXAMPLE_CUSTOMER = {
    "name": "Customer", "age": 26, "profile": "heir",
    "wealth_total": 490000, "cash": 3100, "company_share": 0.82,
    "monthly_income": 3000, "monthly_spending": 2820,
    "monthly_saving_cash": 180, "monthly_saving_invested": 0,
    "crash_reaction": "sell",               # sell | hold | buy  (from the reflex test)
    "disability_cover": False, "will": False,
    "has_buffer_plan": False,               # emergency-pot standing order already verified
    "has_diversification_plan": False,     # family-table plan already agreed
    "goals": [{"type": "wealth", "target": 1000000, "priority": 1}],
    # goal types: "wealth" (reach target by the horizon) | "keep" (do not end below today)
}

# Habit changes the engine can test. Amounts are illustrative product defaults.
LEVERS = {
    "buffer": {"label": "Save €400 a month into a buffer",
               "change": "Standing order of €400 a month into an emergency pot",
               "first_step": "Confirm the prepared standing order: €400 on the 1st of each month into a new emergency pot.",
               "amount": 400},
    "invest": {"label": "Invest €150 a month",
               "change": "Half of each future raise goes into a monthly investment plan, about €150 a month",
               "first_step": "Confirm the save-more-tomorrow commitment: half of your next raise goes into your monthly investment plan.",
               "amount": 150},
    "hold_rule": {"label": "Hold by written rule in a crash",
                  "change": "Follow written rules in a market fall instead of selling",
                  "first_step": "Write down your rules for a falling market with your advisor, then practise them in the crash review."},
    "diversify": {"label": "Diversify the family company shares",
                  "change": "Reduce the single-company share from {share} to 60% over several years",
                  "first_step": "Book the family-table session with your advisor and your parents to agree a step-by-step plan."},
    "cover": {"label": "Get disability cover",
              "change": "Put income-protection cover in place",
              "first_step": "Book the 15-minute income protection check with a specialist."},
}


# ----------------------------------------------------------------------------- formatting (same as the demo)
def js_round(x):
    return math.floor(x + 0.5)


def eur(v):
    return "€" + f"{js_round(v):,}"


def eur_k(v):
    return "€" + str(js_round(v / 1e3)) + "k" if v >= 1e4 else eur(v)


def eur_m(v):
    return "€" + f"{v / 1e6:.2f}" + "m" if abs(v) >= 1e6 else eur_k(v)


def pct(v):
    return str(js_round(v * 100)) + "%"


def _short_m(v):
    s = eur_m(v)
    return s.replace(".00m", "m").replace("0m", "m") if s.endswith("0m") else s


# ----------------------------------------------------------------------------- random numbers (mulberry32, as in the demo)
def _rng(seed):
    M = 0xFFFFFFFF
    a = seed & M

    def imul(x, y):
        return (x * y) & M

    def nxt():
        nonlocal a
        a = (a + 0x6D2B79F5) & M
        t = imul(a ^ (a >> 15), 1 | a)
        t = ((t + imul(t ^ (t >> 7), 61 | t)) & M) ^ t
        return ((t ^ (t >> 14)) & M) / 4294967296
    return nxt


# ----------------------------------------------------------------------------- the simulation
def simulate(c, w, A=ASSUMPTIONS):
    """c: customer intake, w: behaviour for this scenario (see _world). Returns raw results."""
    Y, N = A["years"], A["paths"]
    r = _rng(A["seed"])
    start = c["wealth_total"]
    cap_cash = A["buffer_months"] * c["monthly_spending"]
    gap = 12 * (c["monthly_spending"] - (A["cover_replaces"] * c["monthly_income"] if w["covered"] else 0))
    mk, co_a = A["market"], A["company"]
    sq = math.sqrt(1 - A["rho"] ** 2)
    cols = [[0.0] * N for _ in range(Y + 1)]
    ev_shock = ev_panic = ev_gap = 0
    hits = []
    for n in range(N):
        co = w["share_now"] * start
        cash = w["cash"]
        dep = start - co - cash
        missed = False
        f_s = f_p = f_g = 0
        cols[0][n] = start
        for y in range(1, Y + 1):
            u1 = max(r(), 1e-12)
            u2 = r()
            u3 = r()
            m = math.sqrt(-2 * math.log(u1))
            z1 = m * math.cos(6.283185307 * u2)
            z2 = m * math.sin(6.283185307 * u2)
            rm = math.exp(mk["mu"] - mk["sd"] ** 2 / 2 + mk["sd"] * z1) - 1
            rc = math.exp(co_a["mu"] - co_a["sd"] ** 2 / 2 + co_a["sd"] * (A["rho"] * z1 + sq * z2)) - 1
            ill = u3 < A["p_income_loss"]
            got = min(rm, A["cash_rate"]) if missed else rm     # panic seller misses the rebound
            if rc <= -0.4:
                if not f_s:
                    hits.append(co * -rc / (co + dep + cash))
                f_s = 1
            missed = w["panic"] and rm < A["panic_at"]
            if missed:
                f_p = 1
            if ill and not w["covered"]:
                f_g = 1
            co *= 1 + rc
            dep *= 1 + got
            cash *= 1 + A["cash_rate"]
            if ill:
                cash -= gap
            else:
                cash += w["save_cash"] * 12
                dep += w["save_inv"] * 12
            if cash > cap_cash:                                 # buffer full: the rest is invested
                dep += cash - cap_cash
                cash = cap_cash
            if cash < 0:
                dep += cash
                cash = 0
                if dep < 0:
                    co += dep
                    dep = 0
            if w["glide"]:
                tot = co + dep + cash
                tg = max(A["floor"], w["share_now"] - A["glide"] * y)
                if co > tg * tot:
                    x = co - tg * tot
                    co -= x
                    dep += x
            cols[y][n] = co + dep + cash
        ev_shock += f_s
        ev_panic += f_p
        ev_gap += f_g

    def q(a, p):
        return a[min(len(a) - 1, math.floor(p * len(a)))]
    out = {"p10": [], "p50": [], "p90": []}
    for col in cols:
        a = sorted(col)
        out["p10"].append(q(a, .1))
        out["p50"].append(q(a, .5))
        out["p90"].append(q(a, .9))
    end = cols[Y]
    out["below"] = sum(1 for v in end if v < start) / N
    out["end"] = sorted(end)
    hits.sort()
    out["ev"] = {"shock": ev_shock / N, "panic": ev_panic / N, "gap": ev_gap / N,
                 "hit": hits[len(hits) >> 1] if hits else 0}
    return out


# ----------------------------------------------------------------------------- scenarios
def _world(c):
    return {"share_now": c["company_share"], "cash": c["cash"], "glide": bool(c.get("has_diversification_plan")),
            "save_cash": c["monthly_saving_cash"], "save_inv": c["monthly_saving_invested"],
            "covered": bool(c["disability_cover"]), "panic": c["crash_reaction"] == "sell"}


def open_levers(c):
    """Habit changes the customer has not made yet, in a fixed order."""
    L = []
    if not c.get("has_buffer_plan"):
        L.append("buffer")
    if not c["monthly_saving_invested"]:
        L.append("invest")
    if c["crash_reaction"] == "sell":
        L.append("hold_rule")
    if not c.get("has_diversification_plan"):
        L.append("diversify")
    if not c["disability_cover"]:
        L.append("cover")
    return L


def apply_lever(w, lever):
    w = dict(w)
    if lever == "buffer":
        w["save_cash"] += LEVERS["buffer"]["amount"]
    elif lever == "invest":
        w["save_inv"] = LEVERS["invest"]["amount"]
    elif lever == "hold_rule":
        w["panic"] = False
    elif lever == "diversify":
        w["glide"] = True
    elif lever == "cover":
        w["covered"] = True
    return w


def _goals(c, A):
    out = []
    for i, g in enumerate(c["goals"]):
        gid = "g%d" % (i + 1)
        if g["type"] == "wealth":
            t = _short_m(g["target"])
            out.append({"id": gid, "label": f"Build {t} of wealth by age {c['age'] + A['years']}", "target": t,
                        "horizon_years": A["years"], "priority": g["priority"], "_threshold": g["target"]})
        elif g["type"] == "keep":
            t = eur_m(c["wealth_total"])
            out.append({"id": gid, "label": f"Do not end below today's wealth of {t}", "target": t,
                        "horizon_years": A["years"], "priority": g["priority"], "_threshold": c["wealth_total"]})
        else:
            raise ValueError("unknown goal type: " + str(g["type"]))
    return out


def _results(o, goals, A):
    Y = A["years"]
    gs = {}
    for g in goals:
        gs[g["id"]] = pct(sum(1 for x in o["end"] if x >= g["_threshold"]) / len(o["end"]))
    return {
        "range": eur_m(o["p10"][Y]) + " – " + eur_m(o["p90"][Y]),
        "middle": eur_m(o["p50"][Y]), "weak_future": eur_m(o["p10"][Y]),
        "risk_below_today": pct(o["below"]), "goal_success": gs,
        "events": [
            {"id": "company_shock", "label": "The family company loses 40% or more in a single year",
             "chance": pct(o["ev"]["shock"]), "typical_hit": pct(o["ev"]["hit"]) + " of your total wealth in that year"},
            {"id": "panic_sale", "label": "A market fall of 15% or more in which you sell and miss the rebound",
             "chance": pct(o["ev"]["panic"])},
            {"id": "income_gap", "label": "A year without income and without cover", "chance": pct(o["ev"]["gap"])},
        ],
    }


def world(c):
    """Public: the customer's current behaviour, as used by simulate()."""
    return _world(c)


def outcome(c, w, A=ASSUMPTIONS):
    """Public: display results (range, goal chances, risk, events) for one behaviour w."""
    return _results(simulate(c, w, A), _goals(c, A), A)


def goals_of(c, A=ASSUMPTIONS):
    """Public: the customer's goals with ids and labels, as the agents see them."""
    return [{k: v for k, v in g.items() if not k.startswith("_")} for g in _goals(c, A)]


def habits_of(c):
    """Public: the customer's habits as short display strings."""
    saving = c["monthly_saving_cash"] + c["monthly_saving_invested"]
    return {
        "monthly_saving": eur(saving),
        "crash_reaction": {"sell": "sold everything in the crash test", "hold": "held in the crash test",
                           "buy": "bought more in the crash test"}[c["crash_reaction"]],
        "single_company_share": pct(c["company_share"]),
        "disability_cover": "yes" if c["disability_cover"] else "no",
        "will": "yes" if c.get("will") else "no",
        "savings_rate": pct(saving / c["monthly_income"]) + " of income",
    }


def build_agent_input(c, A=ASSUMPTIONS):
    """Customer intake -> Prediction agent input (schema_version 2)."""
    for k in ("wealth_total", "cash", "company_share", "monthly_income", "monthly_spending",
              "monthly_saving_cash", "monthly_saving_invested", "crash_reaction", "disability_cover", "goals", "age"):
        if k not in c:
            raise ValueError("customer intake is missing: " + k)
    goals = _goals(c, A)
    base = _world(c)
    levers = open_levers(c)
    scen = [{"id": "baseline", "label": "Same habits", "change": None, "kind": "baseline",
             "results": _results(simulate(c, base, A), goals, A)}]
    for lv in levers:
        L = LEVERS[lv]
        scen.append({"id": lv, "label": L["label"], "change": L["change"].format(share=pct(c["company_share"])),
                     "first_step": L["first_step"], "kind": "change",
                     "results": _results(simulate(c, apply_lever(base, lv), A), goals, A)})
    if len(levers) > 1:
        w = base
        for lv in levers:
            w = apply_lever(w, lv)
        scen.append({"id": "full_plan", "label": "Do all of the above", "change": f"All {len(levers)} changes together",
                     "kind": "combo", "results": _results(simulate(c, w, A), goals, A)})
    habits = habits_of(c)
    return {
        "schema_version": 2,
        "customer": {"name": c.get("name", "Customer"), "age": c["age"], "profile": c.get("profile", ""),
                     "habits": habits, "goals": [{k: v for k, v in g.items() if not k.startswith("_")} for g in goals]},
        "horizon_years": A["years"], "paths": A["paths"], "seed": A["seed"], "wealth_now": eur_m(c["wealth_total"]),
        "scenarios": scen,
    }


if __name__ == "__main__":
    cust = EXAMPLE_CUSTOMER
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf8") as f:
            cust = json.load(f)
    print(json.dumps(build_agent_input(cust), indent=2, ensure_ascii=False))
