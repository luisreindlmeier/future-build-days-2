#!/usr/bin/env python3
"""Tests for engine.py.  Run:  python3 test_engine.py
1. Parity: the Python engine gives exactly the same scenario results as the demo's
   JavaScript engine, which produced eval_cases.json.
2. Determinism, sensible behaviour of the levers, goal handling.
3. Pipeline: engine output is valid agent input and the agent's fallback validates.
No network calls; the live model is tested by eval_agent.py."""
import copy
import json
import os
import time
import unittest

import engine as e
import prediction_agent as agent

HERE = os.path.dirname(os.path.abspath(__file__))
CASES = {c["case"]: c for c in json.load(open(os.path.join(HERE, "eval_cases.json"), encoding="utf8"))}

# The intake that corresponds to each demo state in eval_cases.json
BASE = dict(e.EXAMPLE_CUSTOMER)
STATES = {
    "c01": {},
    "c02": {"crash_reaction": "hold", "disability_cover": True,
            "goals": [{"type": "wealth", "target": 1000000, "priority": 1}, {"type": "keep", "priority": 2}]},
    "c03": {"crash_reaction": "buy", "goals": [{"type": "wealth", "target": 1500000, "priority": 1}]},
    "c04": {"goals": [{"type": "keep", "priority": 1}, {"type": "wealth", "target": 750000, "priority": 2}]},
    "c05": {"company_share": 0.70, "cash": 4700, "monthly_saving_cash": 580, "has_buffer_plan": True,
            "has_diversification_plan": True},
    "c06": {"crash_reaction": "hold", "disability_cover": True, "will": True, "company_share": 0.67, "cash": 5100,
            "monthly_saving_cash": 580, "has_buffer_plan": True, "has_diversification_plan": True,
            "goals": [{"type": "wealth", "target": 1000000, "priority": 1}, {"type": "keep", "priority": 2}]},
    "c07": {"disability_cover": True, "goals": [{"type": "wealth", "target": 3000000, "priority": 1}]},
    "c08": {"crash_reaction": "hold", "disability_cover": True, "will": True, "company_share": 0.60, "cash": 6300,
            "monthly_saving_cash": 580, "monthly_saving_invested": 150, "has_buffer_plan": True,
            "has_diversification_plan": True},
}


def customer(case):
    c = copy.deepcopy(BASE)
    c.update(STATES[case])
    return c


class Parity(unittest.TestCase):
    def test_same_results_as_javascript_engine(self):
        for case in STATES:
            with self.subTest(case=case):
                py = e.build_agent_input(customer(case))
                js = CASES[case]["input"]
                self.assertEqual([s["id"] for s in py["scenarios"]], [s["id"] for s in js["scenarios"]])
                for a, b in zip(py["scenarios"], js["scenarios"]):
                    self.assertEqual(a["results"], b["results"], f"{case}/{a['id']}")
                    self.assertEqual(a.get("change"), b.get("change"))
                self.assertEqual(py["customer"]["goals"], js["customer"]["goals"])


class Behaviour(unittest.TestCase):
    def setUp(self):
        self.c = customer("c01")

    def test_deterministic(self):
        self.assertEqual(e.build_agent_input(self.c), e.build_agent_input(self.c))

    def test_levers_offered_only_when_not_done(self):
        self.assertEqual(e.open_levers(self.c), ["buffer", "invest", "hold_rule", "diversify", "cover"])
        self.assertEqual(e.open_levers(customer("c08")), [])
        self.assertNotIn("hold_rule", e.open_levers(customer("c02")))

    def test_levers_do_what_they_say(self):
        sc = {s["id"]: s["results"] for s in e.build_agent_input(self.c)["scenarios"]}
        ev = lambda s, i: next(x["chance"] for x in sc[s]["events"] if x["id"] == i)
        self.assertEqual(ev("hold_rule", "panic_sale"), "0%")
        self.assertEqual(ev("cover", "income_gap"), "0%")
        num = lambda s: int(s.rstrip("%"))
        self.assertLess(num(sc["full_plan"]["risk_below_today"]), num(sc["baseline"]["risk_below_today"]))
        self.assertGreater(num(sc["full_plan"]["goal_success"]["g1"]), num(sc["baseline"]["goal_success"]["g1"]))

    def test_unknown_goal_and_missing_field_rejected(self):
        c = dict(self.c, goals=[{"type": "yacht", "priority": 1}])
        self.assertRaises(ValueError, e.build_agent_input, c)
        c = dict(self.c)
        c.pop("cash")
        self.assertRaises(ValueError, e.build_agent_input, c)

    def test_speed(self):
        t = time.time()
        e.build_agent_input(self.c)
        self.assertLess(time.time() - t, 15, "7 scenarios x 2,000 paths should take a few seconds")


class Pipeline(unittest.TestCase):
    def test_engine_output_is_valid_agent_input(self):
        for case in STATES:
            with self.subTest(case=case):
                inp = e.build_agent_input(customer(case))
                self.assertEqual(agent.check_input(inp), [])
                self.assertEqual(agent.validate(agent.fallback(inp), inp), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
