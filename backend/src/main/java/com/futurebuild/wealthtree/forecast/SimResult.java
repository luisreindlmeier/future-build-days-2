package com.futurebuild.wealthtree.forecast;

import java.util.Map;

/** Percentiles per year (index 0 = today) and event chances over all simulated paths. */
public record SimResult(double[] p10, double[] p50, double[] p90, double belowToday,
                        double companyShock, double panicSale, double incomeGap, double typicalHit,
                        Map<String, Double> goalSuccess) {}
