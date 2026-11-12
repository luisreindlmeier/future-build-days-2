package com.futurebuild.wealthtree.forecast;

/** A wealth goal: total wealth of at least target after horizonYears. */
public record ForecastGoal(String id, String label, double target, int horizonYears, int priority) {}
