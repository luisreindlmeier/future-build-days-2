package com.futurebuild.wealthtree;

import com.futurebuild.wealthtree.forecast.AgentInputBuilder;
import com.futurebuild.wealthtree.forecast.Assumptions;
import com.futurebuild.wealthtree.forecast.ForecastProfiles;
import com.futurebuild.wealthtree.forecast.MonteCarloEngine;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** The Java engine must reproduce the team demo (and prediction-agent/example_input.json) exactly. */
class ForecastEngineTest {

    private final AgentInputBuilder builder = new AgentInputBuilder(new MonteCarloEngine(Assumptions.DEMO));

    @SuppressWarnings("unchecked")
    private Map<String, Object> results(Map<String, Object> input, String scenarioId) {
        return ((List<Map<String, Object>>) input.get("scenarios")).stream()
                .filter(s -> s.get("id").equals(scenarioId)).findFirst().map(s -> (Map<String, Object>) s.get("results")).orElseThrow();
    }

    @Test
    void maxMatchesTheAgentExample() {
        Map<String, Object> in = builder.build(ForecastProfiles.get("max").orElseThrow());
        assertEquals(2, in.get("schema_version"));
        assertEquals("€490k", in.get("wealth_now"));
        Map<String, Object> base = results(in, "baseline");
        assertEquals("€294k – €2.90m", base.get("range"));
        assertEquals("€763k", base.get("middle"));
        assertEquals("28%", base.get("risk_below_today"));
        assertEquals(Map.of("g1", "40%"), base.get("goal_success"));
        Map<String, Object> plan = results(in, "full_plan");
        assertEquals("€506k – €2.87m", plan.get("range"));
        assertEquals("€1.09m", plan.get("middle"));
        assertEquals("9%", plan.get("risk_below_today"));
        assertEquals(Map.of("g1", "55%"), plan.get("goal_success"));
        assertEquals("€382k – €2.62m", results(in, "diversify").get("range"));
    }

    @Test
    void sameSeedGivesSameNumbers() {
        assertEquals(builder.build(ForecastProfiles.get("maya").orElseThrow()).toString(),
                new AgentInputBuilder(new MonteCarloEngine(Assumptions.DEMO)).build(ForecastProfiles.get("maya").orElseThrow()).toString());
    }
}
