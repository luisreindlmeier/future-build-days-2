package com.futurebuild.wealthtree.prediction;

import java.util.Map;

/**
 * The team's Python pipeline (prediction-agent folder): engine -> prediction agent + action agent.
 * In: customer intake. Out: {intake, engine, chart, prediction, actions, kairos} (see tools/kairos_server.py).
 */
public interface KairosBridge {
    Map<String, Object> assessment(Map<String, Object> intake) throws Exception;
    default Map<String, Object> projects(Map<String, Object> request) throws Exception {
        throw new UnsupportedOperationException("Projects bridge not configured");
    }
}

