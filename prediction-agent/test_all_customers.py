#!/usr/bin/env python3
"""End-to-end check: every sample customer, rules-only and live AI, through the same path as the playground.

    python3 test_all_customers.py          (or: pytest test_all_customers.py)
    SKIP_AI=1 python3 test_all_customers.py     rules-only, no network

For every output it asserts: no errors, no raw ids in customer-facing text, no forbidden words, every
number traceable to the facts of the part it appears in (the agents' own validators), and "freed"
money that excludes buffer and saving transfers. Live AI needs HIP_API_KEY in .env.
"""
import concurrent.futures as cf
import os
import random
import re
import tempfile
import unittest

import guardrails as G
G.LOG_FILE = os.path.join(tempfile.gettempdir(), "guardrail-test.log")   # keep the demo log clean
import action_agent as A          # noqa: E402
import playground as pg           # noqa: E402
import prediction_agent as P      # noqa: E402

MODES = ["fallback"] + ([] if os.environ.get("SKIP_AI") or not P._cfg()["key"] else ["ai"])
RESULTS = {}


def _run(job):
    name, mode = job
    c = dict(pg.PRESETS[name], name="Test-%05d" % random.randrange(10 ** 5))   # unique: no gateway cache
    return job, pg.run(c, pg.MODELS[0], mode)


def setUpModule():
    jobs = [(n, m) for n in pg.PRESETS for m in MODES]
    with cf.ThreadPoolExecutor(6) as ex:
        for job, res in ex.map(_run, jobs):
            RESULTS[job] = res


def shown_text(res):
    """Everything the playground shows the customer as text (not the raw JSON debug panels)."""
    sc = {s["id"]: s["label"] for s in res["engine"]["input"]["scenarios"]}
    t = list(sc.values())
    o = res["prediction"]["output"]
    t += [o["headline"], o["if_nothing_changes"], o["future_selves"]["same_habits"], o["future_selves"]["with_changes"],
          *o["what_it_means"], o.get("trade_off") or "", o["disclaimer"]]
    if o.get("best_change"):
        t += [sc[o["best_change"]["scenario_id"]], o["best_change"]["why"], o["best_change"]["first_step"]]
    t += [g["sentence"] for g in o["goals"]] + [c["what_happens"] for c in o["comparison"]]
    if o.get("watch_out"):
        t.append(o["watch_out"]["sentence"])
    a = res["action"]["output"]
    if a:
        t += [a["intro"], a["disclaimer"]] + [x["title"] for x in res["action_input"]["not_shown"]]
        for x in a["actions"]:
            t += [x["title"], x["why"], x["how"], x["verified_by"], x["effort"], x["impact"]["effect_label"]]
        if a.get("advisor_meeting"):
            t.append(a["advisor_meeting"]["sentence"])
    return [x for x in t if x]


class AllCustomers(unittest.TestCase):
    def each(self):
        for (name, mode), res in sorted(RESULTS.items()):
            yield f"{name.split(' ·')[0]} / {'rules' if mode == 'fallback' else 'AI'}", mode, res

    def test_runs_and_sources(self):
        for tag, mode, res in self.each():
            with self.subTest(tag):
                for agent in ("prediction", "action"):
                    src = res[agent]["source"]
                    if mode == "fallback":
                        self.assertEqual(src, "rules", agent)
                    else:
                        self.assertIn(src, ("ai", "ai_partial", "fallback", "rules"), agent)
                        self.assertNotIn("TypeError", " ".join(res[agent].get("problems", [])))

    def test_no_raw_ids(self):
        for tag, _, res in self.each():
            with self.subTest(tag):
                for text in shown_text(res):
                    self.assertFalse(G.RAW_ID.findall(text), f"raw id in: {text}")

    def test_no_forbidden_words(self):
        for tag, _, res in self.each():
            with self.subTest(tag):
                for text in shown_text(res):
                    m = G.FORBIDDEN.search(text)
                    self.assertIsNone(m, f"forbidden '{m and m.group(0)}' in: {text}")

    def test_numbers_traceable(self):
        for tag, _, res in self.each():
            with self.subTest(tag):
                inp = res["engine"]["input"]
                self.assertEqual(P.validate_fields(res["prediction"]["output"], inp), {})
                a = res["action"]["output"]
                if a:
                    plan = A.build_action_input(dict(res["engine"]["customer"]))
                    words = {"intro": a["intro"], "actions": [{"action_id": x["action_id"], "why": x["why"]} for x in a["actions"]],
                             "advisor_meeting": a["advisor_meeting"] and {"sentence": a["advisor_meeting"]["sentence"]}}
                    self.assertEqual(A.validate_fields(words, plan), {})

    def test_freed_excludes_transfers(self):
        for tag, _, res in self.each():
            with self.subTest(tag):
                qw, plan = res["action_input"]["quick_wins"], res["action_input"]["plan"]
                if not qw:
                    continue
                week = [x for x in plan if x["bucket"] == "this_week"]
                freed = sum(P._money(x["impact"]["monthly"]) for x in week if x["impact"].get("money_kind") == "freed")
                self.assertEqual(P._money(qw["freed_per_month"] or "€0"), freed)
                for x in week:
                    if x["id"] in ("start_buffer", "save_more_tomorrow"):
                        self.assertEqual(x["impact"]["money_kind"], "set_aside")
                aside = P._money(qw["set_aside_per_month"] or "€0")
                if aside:
                    intro = res["action"]["output"]["intro"]
                    wrong = [t for t in G.numbers(intro) if t[0] == "eur" and abs(t[1] - (freed + aside)) < 1]
                    self.assertFalse(wrong, f"intro counts the buffer as freed: {intro}")

    def test_intake_is_consistent(self):
        for tag, _, res in self.each():
            with self.subTest(tag):
                self.assertEqual(res["intake_warnings"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
