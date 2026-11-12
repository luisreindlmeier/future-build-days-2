package com.futurebuild.wealthtree.forecast;

import java.util.List;
import java.util.Map;

/**
 * What the forecast engine needs about one customer.
 * profile: "heir" | "founder" | "pro" (same words as the demo and the prediction agent).
 */
public record ForecastProfile(
        String id, String name, int age, String profile, int horizonYears,
        Finances finances, World baseline,
        Map<String, String> habits,
        List<ForecastGoal> goals,
        List<PlannedChange> changes
) {}
