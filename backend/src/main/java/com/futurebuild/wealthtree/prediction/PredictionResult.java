package com.futurebuild.wealthtree.prediction;

import java.time.Instant;
import java.util.Map;

/**
 * status RUNNING:     the pipeline is working (10-25 s with live AI); intake is already there, poll again.
 * status READY:       engine + chart + prediction agent + action agent + kairos (projects-section format).
 * status UNAVAILABLE: the Python bridge is not running; intake is there, error says how to start it.
 */
public record PredictionResult(
        String userId,
        Status status,
        Map<String, Object> intake,
        Object engine,
        Object chart,
        Object prediction,
        Object actions,
        Object kairos,
        String error,
        Instant updatedAt
) {
    public enum Status { RUNNING, READY, UNAVAILABLE }
}
