package com.futurebuild.wealthtree.forecast;

import java.util.function.UnaryOperator;

/** One habit change = one "change" scenario for the prediction agent. */
public record PlannedChange(String id, String label, String change, String firstStep, UnaryOperator<World> apply) {}
