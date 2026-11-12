package com.futurebuild.wealthtree.assessment;

import com.futurebuild.wealthtree.model.SpendingCategory;

public record SpendingHabit(
        SpendingCategory category,
        double monthlyAverage,
        double monthlyBudget,      // upper end of the healthy range = 1.25 × peer average
        double peerAverage,        // what households with the same net income spend (Destatis)
        String peerGroup,
        double trendPct,      // last 3 months vs first 3 months, e.g. 0.38 = +38%
        HabitHealth health,
        String reason
) {}
