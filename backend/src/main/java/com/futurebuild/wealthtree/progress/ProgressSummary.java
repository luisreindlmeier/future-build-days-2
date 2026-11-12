package com.futurebuild.wealthtree.progress;

import java.io.Serializable;
import java.time.YearMonth;
import java.util.List;

/** What the frontend needs to show growth: trend, changes, latest events, milestones, action status. */
public record ProgressSummary(
        YearMonth month,
        int monthsTracked,
        Integer healthChangeLastMonth,
        Integer healthChangeSinceStart,
        Trend trend,
        List<String> latestEvents,
        List<String> milestones,
        List<TrackedAction> actions
) implements Serializable {
    public enum Trend { GROWING, STABLE, SHRINKING, NEW }
}
