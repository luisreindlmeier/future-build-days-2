package com.futurebuild.wealthtree.forecast;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static com.futurebuild.wealthtree.forecast.Fmt.eurM;
import static com.futurebuild.wealthtree.forecast.Fmt.pct;

/**
 * Builds the prediction agent's INPUT CONTRACT (schema_version 2) from the engine.
 * Every figure is a display string produced here; the agent never calculates.
 */
public class AgentInputBuilder {

    private final MonteCarloEngine engine;

    public AgentInputBuilder(MonteCarloEngine engine) {
        this.engine = engine;
    }

    public Map<String, Object> build(ForecastProfile p) {
        Map<String, Object> customer = new LinkedHashMap<>();
        customer.put("name", "Customer");          // pseudonymous towards the AI gateway
        customer.put("age", p.age());
        customer.put("profile", p.profile());
        customer.put("habits", p.habits());
        List<Map<String, Object>> goals = new ArrayList<>();
        for (ForecastGoal g : p.goals()) {
            Map<String, Object> gm = new LinkedHashMap<>();
            gm.put("id", g.id());
            gm.put("label", g.label());
            gm.put("target", Fmt.target(g.target()));
            gm.put("horizon_years", g.horizonYears());
            gm.put("priority", g.priority());
            goals.add(gm);
        }
        customer.put("goals", goals);

        Map<String, Object> in = new LinkedHashMap<>();
        in.put("schema_version", 2);
        in.put("customer", customer);
        in.put("horizon_years", p.horizonYears());
        in.put("paths", engine.assumptions().paths());
        in.put("seed", engine.assumptions().seed());
        in.put("wealth_now", eurM(p.finances().total()));

        List<Map<String, Object>> scenarios = new ArrayList<>();
        scenarios.add(scenario(p, "baseline", "Same habits", null, null, "baseline", p.baseline()));
        World all = p.baseline();
        for (PlannedChange c : p.changes()) {
            scenarios.add(scenario(p, c.id(), c.label(), c.change(), c.firstStep(), "change", c.apply().apply(p.baseline())));
            all = c.apply().apply(all);
        }
        if (p.changes().size() > 1) {
            scenarios.add(scenario(p, "full_plan", "Do all of the above", "All " + p.changes().size() + " changes together", null, "combo", all));
        }
        in.put("scenarios", scenarios);
        return in;
    }

    /** Fan chart data for the frontend: percentiles per year, today's path vs. full plan. */
    public Map<String, Object> chart(ForecastProfile p) {
        World all = p.baseline();
        for (PlannedChange c : p.changes()) all = c.apply().apply(all);
        SimResult now = sim(p, p.baseline()), plan = sim(p, all);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("startAge", p.age());
        m.put("years", p.horizonYears());
        m.put("wealthNow", p.finances().total());
        m.put("todayPath", Map.of("p10", now.p10(), "p50", now.p50(), "p90", now.p90(), "riskBelowToday", now.belowToday()));
        m.put("fullPlan", Map.of("p10", plan.p10(), "p50", plan.p50(), "p90", plan.p90(), "riskBelowToday", plan.belowToday()));
        return m;
    }

    private SimResult sim(ForecastProfile p, World w) {
        return engine.simulate(p.finances(), w, p.horizonYears(), p.goals());
    }

    private Map<String, Object> scenario(ForecastProfile p, String id, String label, String change, String firstStep, String kind, World w) {
        SimResult r = sim(p, w);
        int Y = p.horizonYears();
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("range", eurM(r.p10()[Y]) + " – " + eurM(r.p90()[Y]));
        res.put("middle", eurM(r.p50()[Y]));
        res.put("weak_future", eurM(r.p10()[Y]));
        res.put("risk_below_today", pct(r.belowToday()));
        Map<String, String> gs = new LinkedHashMap<>();
        r.goalSuccess().forEach((k, v) -> gs.put(k, pct(v)));
        res.put("goal_success", gs);
        List<Map<String, Object>> events = new ArrayList<>();
        if (p.baseline().shareNow() > 0) {
            Map<String, Object> e = event("company_shock", "The family company loses 40% or more in a single year", r.companyShock());
            e.put("typical_hit", pct(r.typicalHit()) + " of your total wealth in that year");
            events.add(e);
        }
        events.add(event("panic_sale", "A market fall of 15% or more in which you sell and miss the rebound", r.panicSale()));
        events.add(event("income_gap", "A year without income and without cover", r.incomeGap()));
        res.put("events", events);

        Map<String, Object> s = new LinkedHashMap<>();
        s.put("id", id);
        s.put("label", label);
        s.put("change", change);
        if (firstStep != null) s.put("first_step", firstStep);
        s.put("kind", kind);
        s.put("results", res);
        return s;
    }

    private static Map<String, Object> event(String id, String label, double chance) {
        Map<String, Object> e = new LinkedHashMap<>();
        e.put("id", id);
        e.put("label", label);
        e.put("chance", pct(chance));
        return e;
    }
}
