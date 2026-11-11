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

ENGINE_VERSION = "1.1"

ASSUMPTIONS = {
    "years": 15, "paths": 2000, "seed": 260841,
    "company": {"mu": 0.07, "sd": 0.30},     # single family company: average return, yearly swings
    "market": {"mu": 0.06, "sd": 0.15},      # broad diversified market
    "rho": 0.3,                              # how strongly company and market move together
    "cash_rate": 0.015,
    "p_income_loss": 0.004,                  # chance per year of a year without income
    "panic_at": -0.15,                       # market fall that triggers a panic sale
    # Panic-sale model. A customer who "sold everything" in the reflex test sells all invested money
    # at the end of a year in which the market fell 15% or more (so they take the fall), then stays in
    # cash for `panic_out_years` full years and buys back in only after that. Recoveries after big falls
    # are typically strongest in the first one or two years, so this is when the seller misses most.
    # Two years is our assumption for a typical late re-entry; set 1 for a milder view. New savings in
    # that period also sit in cash. Company shares are not sold (they usually cannot be sold quickly).
    # "legacy" reproduces the demo engine: out for one year, and that year still takes market losses.
    "panic_model": "out_of_market", "panic_out_years": 2,
    # Rebound: yearly returns are otherwise drawn independently, so without this a crash would never be
    # followed by a recovery and missing it would cost almost nothing. After a market fall of 15% or more,
    # next year's expected market return is raised by `rebound` x the size of the fall (0.5 after a -30%
    # year adds +15 points on average; the yearly swing stays the same). It applies to everyone in the
    # same futures; only a panic seller sitting in cash misses it. Assumption, not a forecast; 0 turns it off.
    "rebound": 0.5,
    "glide": 0.11, "floor": 0.60,            # diversification: points per year, target share
    "buffer_months": 3,                      # emergency buffer target: cash above this many months of
                                             # spending is not kept as cash but invested
    "cover_replaces": 0.6,                   # share of income paid by disability cover
}

# The demo's JavaScript engine (checkup-demo.html) used these; test_engine.py checks parity with them.
LEGACY_ASSUMPTIONS = dict(ASSUMPTIONS, buffer_months=6, panic_model="legacy", rebound=0.0)

# Intake for one customer. Amounts in EUR per month unless stated.
EXAMPLE_CUSTOMER = {
    "name": "Customer", "age": 26, "profile": "heir",
    "wealth_total": 490000, "cash": 3100, "company_share": 0.82,
    "monthly_income": 3400, "income_note": "salary €3,000 + family dividends €400",
    "monthly_spending": 2820,
    "monthly_saving_cash": 180, "monthly_saving_invested": 0,
    "crash_reaction": "sell",               # sell | hold | buy  (from the reflex test)
    "disability_cover": False, "will": False,
    "has_buffer_plan": False,               # emergency-pot standing order already verified
    "has_diversification_plan": False,     # family-table plan already agreed
    "buffer_amount": 400, "invest_amount": 150,   # optional; default 10% / 5% of income
    "horizon_years": 15,                    # optional; default ASSUMPTIONS["years"]
    "goals": [{"type": "wealth", "target": 1000000, "priority": 1}],
    # goal types: "wealth"  reach target (total wealth) by the horizon
    #             "keep"    do not end below today's wealth
    #             "home"    have target in cash + investments (not company shares) after "years" years
    #                       e.g. {"type": "home", "target": 90000, "years": 5, "priority": 1}
    # profile: "heir" | "founder" | "pro"  (changes how the single-company risk is named and handled)
}

HOLDING = {   # how the single big holding is called, per profile
    "heir": {"name": "The family company", "short": "the family company shares", "whose": "family company shares"},
    "founder": {"name": "Your own company", "short": "your own company stake", "whose": "your company stake"},
    "pro": {"name": "Your largest single holding", "short": "your largest single holding", "whose": "your largest holding"},
}

# Habit changes the engine can test. Amounts are illustrative product defaults.
LEVERS = {
    "close_gap": {"label": "Spend no more than you earn",
                  "change": "Bring monthly spending down to your income, closing a {gap} monthly gap",
                  "first_step": "Review your three largest spending categories in the app and set limits until income covers spending again."},
    "buffer": {"label": "Save {buf} a month into a buffer",
               "change": "Standing order of {buf} a month into an emergency pot until it covers {cap} months of spending, then into investments",
               "first_step": "Confirm the prepared standing order: {buf} on the 1st of each month into a new emergency pot."},
    "invest": {"label": "Invest {inv} a month",
               "change": "Half of each future raise goes into a monthly investment plan, about {inv} a month",
               "first_step": "Confirm the save-more-tomorrow commitment: half of your next raise goes into your monthly investment plan."},
    "hold_rule": {"label": "Hold by written rule in a crash",
                  "change": "Follow written rules in a market fall instead of selling",
                  "first_step": "Write down your rules for a falling market with your advisor, then practise them in the crash review."},
    "diversify": {"label": "Diversify {short}",
                  "change": "Reduce the single-company share from {share} to 60% over several years",
                  "first_step": {
                      "heir": "Book the family-table session with your advisor and your parents to agree a step-by-step plan.",
                      "founder": "Book an advisor session to plan how your stake can be lowered step by step, for example around the next funding round.",
                      "pro": "Book an advisor session to agree a step-by-step plan for your largest single holding."}},
    "cover": {"label": "Get disability cover",
              "change": "Put income-protection cover in place",
              "first_step": "Book the 15-minute income protection check with a specialist."},
}


def _round50(x):
    return int(math.floor(x / 50 + 0.5)) * 50


def amounts(c):
    """Monthly amounts for the saving levers: from the intake, else scaled to income."""
    return {"buf": c.get("buffer_amount") or max(100, _round50(0.10 * c["monthly_income"])),
            "inv": c.get("invest_amount") or max(50, _round50(0.05 * c["monthly_income"]))}


def holding(c):
    return HOLDING.get(c.get("profile"), HOLDING["pro"])


def lever_text(c, lever):
    """Label, change and first step of a lever, filled in for this customer."""
    L, a, h = LEVERS[lever], amounts(c), holding(c)
    gap = -(c["monthly_saving_cash"] + c["monthly_saving_invested"])
    f = dict(cap=ASSUMPTIONS["buffer_months"], buf=eur(a["buf"]), inv=eur(a["inv"]), share=pct(c["company_share"]), short=h["short"], gap=eur(max(0, gap)))
    fs = L["first_step"]
    if isinstance(fs, dict):
        fs = fs.get(c.get("profile"), fs["pro"])
    return {"label": L["label"].format(**f), "change": L["change"].format(**f), "first_step": fs.format(**f)}


def intake_warnings(c, A=ASSUMPTIONS):
    """Plausibility checks on the intake. They warn, they never block."""
    w = []
    inc, sp = c["monthly_income"], c["monthly_spending"]
    sav = c["monthly_saving_cash"] + c["monthly_saving_invested"]
    if sav >= 0 and sav + sp > inc + 1:
        w.append(f"Saving ({eur(sav)}) plus spending ({eur(sp)}) is more than income ({eur(inc)}) a month.")
    if sav < 0 and abs(sp - inc - sav) > 1 and abs(sp - inc + sav) > 1 and sp - inc != -sav:
        w.append(f"Spending ({eur(sp)}) minus income ({eur(inc)}) does not match the monthly shortfall ({eur(-sav)}).")
    if not 0 <= c["company_share"] <= 1:
        w.append(f"Company share {pct(c['company_share'])} is not between 0% and 100%.")
    elif c["company_share"] * c["wealth_total"] + c["cash"] > c["wealth_total"] + 1:
        w.append(f"Company shares ({eur_m(c['company_share'] * c['wealth_total'])}) plus cash ({eur(c['cash'])}) "
                 f"are more than total wealth ({eur_m(c['wealth_total'])}).")
    free = inc - sp - sav
    lv = open_levers(c, A)
    if "buffer" in lv and amounts(c)["buf"] > free + 1:
        w.append(f"The buffer step ({eur(amounts(c)['buf'])} a month) is more than what is left after spending and saving "
                 f"({eur(max(0, free))}): it needs spending cuts to be affordable.")
    return w


def assumptions_for(c, A=ASSUMPTIONS):
    """The customer's own horizon, if given."""
    h = c.get("horizon_years")
    return A if not h or h == A["years"] else dict(A, years=int(h))


# ----------------------------------------------------------------------------- formatting (same as the demo)
def js_round(x):
    return math.floor(x + 0.5)


def eur(v):
    return ("−€" if v < 0 else "€") + f"{abs(js_round(v)):,}"


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
    liq = [[0.0] * N for _ in range(Y + 1)]          # cash + investments, without company shares
    has_co = w["share_now"] > 0
    legacy = A.get("panic_model") == "legacy"
    ev_shock = ev_panic = ev_gap = 0
    hits = []
    for n in range(N):
        co = w["share_now"] * start
        cash = w["cash"]
        dep = start - co - cash
        missed = False
        out = 0                                          # years left in cash after a panic sale
        prev_rm = 0.0                                    # last year's market return, for the rebound
        f_s = f_p = f_g = 0
        cols[0][n] = start
        liq[0][n] = dep + cash
        for y in range(1, Y + 1):
            u1 = max(r(), 1e-12)
            u2 = r()
            u3 = r()
            m = math.sqrt(-2 * math.log(u1))
            z1 = m * math.cos(6.283185307 * u2)
            z2 = m * math.sin(6.283185307 * u2)
            boost = A.get("rebound", 0) * -prev_rm if prev_rm < A["panic_at"] else 0.0
            rm = math.exp(mk["mu"] + boost - mk["sd"] ** 2 / 2 + mk["sd"] * z1) - 1
            rc = math.exp(co_a["mu"] - co_a["sd"] ** 2 / 2 + co_a["sd"] * (A["rho"] * z1 + sq * z2)) - 1
            ill = u3 < A["p_income_loss"]
            prev_rm_this = rm
            if legacy:
                got = min(rm, A["cash_rate"]) if missed else rm
            else:
                got = A["cash_rate"] if out > 0 else rm         # panic seller sits in cash, misses the rebound
            if has_co and rc <= -0.4:
                if not f_s:
                    hits.append(co * -rc / (co + dep + cash))
                f_s = 1
            if legacy:
                missed = w["panic"] and rm < A["panic_at"]
                if missed:
                    f_p = 1
            elif out > 0:
                out -= 1
            elif w["panic"] and rm < A["panic_at"]:
                out = A["panic_out_years"]
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
            liq[y][n] = dep + cash
            prev_rm = prev_rm_this
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
    out["liq"] = liq
    hits.sort()
    out["ev"] = {"shock": ev_shock / N, "panic": ev_panic / N, "gap": ev_gap / N,
                 "hit": hits[len(hits) >> 1] if hits else 0}
    return out


# ----------------------------------------------------------------------------- scenarios
def _world(c):
    return {"share_now": c["company_share"], "cash": c["cash"], "glide": bool(c.get("has_diversification_plan")),
            "save_cash": c["monthly_saving_cash"], "save_inv": c["monthly_saving_invested"],
            "covered": bool(c["disability_cover"]), "panic": c["crash_reaction"] == "sell", **amounts(c)}


def open_levers(c, A=ASSUMPTIONS):
    """Habit changes the customer has not made yet, in a fixed order."""
    L = []
    if c["monthly_saving_cash"] + c["monthly_saving_invested"] < 0:
        L.append("close_gap")          # first stop the leak; saving more makes no sense before that
    elif not c.get("has_buffer_plan") and c["cash"] < A["buffer_months"] * c["monthly_spending"]:
        L.append("buffer")
    if not c["monthly_saving_invested"] and c["monthly_saving_cash"] >= 0:
        L.append("invest")
    if c["crash_reaction"] == "sell":
        L.append("hold_rule")
    if not c.get("has_diversification_plan") and c["company_share"] > A["floor"] + 0.05:
        L.append("diversify")
    if not c["disability_cover"]:
        L.append("cover")
    return L


def apply_lever(w, lever):
    w = dict(w)
    if lever == "close_gap":
        total = w["save_cash"] + w["save_inv"]
        if total < 0:
            w["save_cash"] -= total
    elif lever == "buffer":
        w["save_cash"] += w["buf"]
    elif lever == "invest":
        w["save_inv"] = w["inv"]
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
        elif g["type"] == "home":
            yrs = int(g.get("years", A["years"]))
            if not 1 <= yrs <= A["years"]:
                raise ValueError(f"home goal years must be between 1 and {A['years']}")
            t = _short_m(g["target"])
            out.append({"id": gid, "label": f"Have {t} saved for a home in {yrs} years", "target": t,
                        "horizon_years": yrs, "priority": g["priority"], "_threshold": g["target"], "_liquid_year": yrs})
        elif g["type"] == "keep":
            t = eur_m(c["wealth_total"])
            out.append({"id": gid, "label": f"Do not end below today's wealth of {t}", "target": t,
                        "horizon_years": A["years"], "priority": g["priority"], "_threshold": c["wealth_total"]})
        else:
            raise ValueError("unknown goal type: " + str(g["type"]))
    return out


def _results(o, goals, A, c=None):
    Y = A["years"]
    gs = {}
    for g in goals:
        pool = o["liq"][g["_liquid_year"]] if "_liquid_year" in g else o["end"]
        gs[g["id"]] = pct(sum(1 for x in pool if x >= g["_threshold"]) / len(pool))
    events = []
    if c is None or c["company_share"] > 0:
        events.append({"id": "company_shock", "label": holding(c or {"profile": "heir"})["name"] + " loses 40% or more in a single year",
                       "chance": pct(o["ev"]["shock"]), "typical_hit": pct(o["ev"]["hit"]) + " of your total wealth in that year"})
    return {
        "range": eur_m(o["p10"][Y]) + " – " + eur_m(o["p90"][Y]),
        "middle": eur_m(o["p50"][Y]), "weak_future": eur_m(o["p10"][Y]),
        "risk_below_today": pct(o["below"]), "goal_success": gs,
        "events": events + [
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
    A = assumptions_for(c, A)
    return _results(simulate(c, w, A), _goals(c, A), A, c)


def goals_of(c, A=ASSUMPTIONS):
    """Public: the customer's goals with ids and labels, as the agents see them."""
    return [{k: v for k, v in g.items() if not k.startswith("_")} for g in _goals(c, assumptions_for(c, A))]


def habits_of(c):
    """Public: the customer's habits as short display strings."""
    saving = c["monthly_saving_cash"] + c["monthly_saving_invested"]
    return {
        "monthly_saving": eur(saving),
        "crash_reaction": {"sell": "sold everything in the crash test", "hold": "held in the crash test",
                           "buy": "bought more in the crash test"}[c["crash_reaction"]],
        **({"single_company_share": pct(c["company_share"]) + " in " + holding(c)["short"].replace("your ", "")}
           if c["company_share"] > 0 else {"single_company_share": "none"}),
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
    A = assumptions_for(c, A)
    goals = _goals(c, A)
    base = _world(c)
    levers = open_levers(c, A)
    scen = [{"id": "baseline", "label": "Same habits", "change": None, "kind": "baseline",
             "results": _results(simulate(c, base, A), goals, A, c)}]
    for lv in levers:
        L = lever_text(c, lv)
        scen.append({"id": lv, "label": L["label"], "change": L["change"],
                     "first_step": L["first_step"], "kind": "change",
                     "results": _results(simulate(c, apply_lever(base, lv), A), goals, A, c)})
    if len(levers) > 1:
        w = base
        for lv in levers:
            w = apply_lever(w, lv)
        scen.append({"id": "full_plan", "label": "Do all of the above", "change": f"All {len(levers)} changes together",
                     "kind": "combo", "results": _results(simulate(c, w, A), goals, A, c)})
    habits = habits_of(c)
    return {
        "schema_version": 2,
        "customer": {"name": c.get("name", "Customer"), "age": c["age"], "profile": c.get("profile", ""),
                     "purpose": c.get("purpose", ""),
                     "money": {"monthly_income": eur(c["monthly_income"]), "monthly_spending": eur(c["monthly_spending"]),
                               "cash": eur(c["cash"]), **({"income_note": c["income_note"]} if c.get("income_note") else {})},
                     "habits": habits, "goals": [{k: v for k, v in g.items() if not k.startswith("_")} for g in goals]},
        "intake_warnings": intake_warnings(c, A),
        "horizon_years": A["years"], "horizon": f"{A['years']} years", "paths": A["paths"], "seed": A["seed"],
        "wealth_now": eur_m(c["wealth_total"]),
        "scenarios": scen,
    }


if __name__ == "__main__":
    cust = EXAMPLE_CUSTOMER
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf8") as f:
            cust = json.load(f)
    print(json.dumps(build_agent_input(cust), indent=2, ensure_ascii=False))
