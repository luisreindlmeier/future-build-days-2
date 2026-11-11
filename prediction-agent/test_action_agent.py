#!/usr/bin/env python3
"""Offline tests for action_agent.py (no network).  Run:  python3 test_action_agent.py"""
import copy, json, unittest
import engine as E
import action_agent as A

MAX = dict(E.EXAMPLE_CUSTOMER, spending=A.EXAMPLE_SPENDING)


def plan_ids(c):
    return [a["id"] for a in A.build_action_input(c)["plan"]]


class Rules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inp = A.build_action_input(MAX)
        cls.by = {a["id"]: a for a in cls.inp["plan"]}

    def test_triggers_fire_on_the_data(self):
        for i in ("start_buffer", "pause_purchase", "limit_eating_out", "cancel_unused_subscriptions",
                  "write_will", "family_diversification_plan", "write_crash_rules", "income_protection_check"):
            self.assertIn(i, self.by, i)

    def test_only_unused_subscriptions_and_only_categories_far_above_peers(self):
        how = self.by["cancel_unused_subscriptions"]["how"]
        self.assertIn("Gym premium", how)
        self.assertIn("Car-sharing plus", how)
        self.assertNotIn("Streaming", how)            # used 2 days ago
        self.assertNotIn("limit_shopping", self.by)    # €240 vs €210 is not far above

    def test_investment_topics_go_to_the_advisor(self):
        for i in ("family_diversification_plan", "write_crash_rules", "income_protection_check"):
            self.assertEqual(self.by[i]["bucket"], "with_your_advisor")
        self.assertEqual(self.inp["advisor_topics"], [a["id"] for a in self.inp["plan"] if a["type"] == "advisor"])

    def test_groups_in_order_and_capped(self):
        b = [a["bucket"] for a in self.inp["plan"]]
        self.assertEqual(b, sorted(b, key=A.BUCKETS.index))
        for k, n in A.RULES["max_per_bucket"].items():
            self.assertLessEqual(b.count(k), n)

    def test_impact_comes_from_the_engine(self):
        im = self.by["pause_purchase"]["impact"]
        self.assertNotEqual(im["main_goal_chance_if_bought_now"], im["main_goal_chance_if_paused"])
        self.assertEqual(self.by["write_crash_rules"]["impact"]["event"]["chance_after"], "0%")

    def test_actions_disappear_when_done(self):
        done = dict(MAX, crash_reaction="hold", disability_cover=True, will=True, has_buffer_plan=True,
                    has_diversification_plan=True, monthly_saving_invested=150, cash=9000,
                    spending={"subscriptions": [], "categories": [], "planned_purchases": []})
        self.assertEqual(plan_ids(done), [])
        thin = dict(MAX, cash=9000)                    # 3.2 months of buffer: no need to pause the car
        self.assertNotIn("pause_purchase", plan_ids(thin))


class Validator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inp = A.build_action_input(MAX)
        cls.good = A.fallback_words(cls.inp)

    def bad(self, f):
        x = copy.deepcopy(self.good)
        f(x)
        return A.validate(x, self.inp)

    def test_fallback_is_valid(self):
        self.assertEqual(A.validate(self.good, self.inp), [])

    def test_rejects(self):
        cases = {
            "sell shares": lambda x: x["actions"][0].update(why="Sell some of your company shares now."),
            "buy a fund": lambda x: x["actions"][0].update(why="Buy a world ETF with the money."),
            "invented figure": lambda x: x.update(intro="You can save €900 a month."),
            "invented points": lambda x: x["actions"][0].update(why="It raises your chance by 12 points."),
            "promise": lambda x: x.update(intro="You will definitely reach your goal."),
            "reordered": lambda x: x["actions"].reverse(),
            "missing action": lambda x: x["actions"].pop(),
            "no advisor sentence": lambda x: x.update(advisor_meeting=None),
            "too long": lambda x: x.update(intro=" ".join(["word"] * 50)),
        }
        for name, f in cases.items():
            with self.subTest(name=name):
                self.assertTrue(self.bad(f), name)

    def test_allows_spending_words(self):
        ok = lambda x: x["actions"][1].update(why="Pausing the car keeps your buffer intact before you buy anything big.")
        self.assertEqual(self.bad(ok), [])

    def test_recommend_falls_back_safely(self):
        r = A.recommend(self.inp, call=lambda c, m: "not json")
        self.assertEqual(r["source"], "fallback")
        self.assertEqual(len(r["output"]["actions"]), len(self.inp["plan"]))
        self.assertIsNotNone(r["output"]["advisor_meeting"])
        good = json.dumps(self.good)
        r = A.recommend(self.inp, call=lambda c, m: good)
        self.assertEqual(r["source"], "ai")
        self.assertEqual(r["output"]["actions"][0]["title"], self.inp["plan"][0]["title"])  # titles from rules


if __name__ == "__main__":
    unittest.main(verbosity=2)
