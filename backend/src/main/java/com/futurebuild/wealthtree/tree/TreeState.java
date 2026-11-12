package com.futurebuild.wealthtree.tree;

import com.futurebuild.wealthtree.progress.ProgressSummary;
import com.futurebuild.wealthtree.scanner.WellBeing;

import java.util.List;

/**
 * The single object the frontend renders. All visual parameters are normalised (0..1)
 * so the 2.5D renderer only maps them to sprites, sizes and animations.
 */
public record TreeState(
        String userId,
        String name,
        Stage stage,
        int overallHealth,
        PartStatus status,
        String headline,
        List<Root> roots,
        Trunk trunk,
        List<LeafCluster> leaves,
        List<Branch> branches,
        Soil soil,
        Weather weather,
        List<String> blossoms,
        WellBeing wellbeing,         // CFPB scanner result (predicted score, percentiles, dimensions); null if not scanned
        ProgressSummary progress     // growth over time: trend, changes, events, milestones, action status; null if not tracked
) {
    /** Adds the remembered progress; milestones become permanent blossoms. */
    public TreeState withProgress(ProgressSummary p) {
        if (p == null) return this;
        java.util.List<String> b = new java.util.ArrayList<>(blossoms);
        for (String m : p.milestones()) {
            b.removeIf(m::startsWith);          // "3-month safety buffer reached" -> the dated milestone replaces it
            if (!b.contains(m)) b.add(m);
        }
        return new TreeState(userId, name, stage, overallHealth, status, headline, roots, trunk, leaves, branches, soil, weather,
                java.util.List.copyOf(b), wellbeing, p);
    }

    /** Sprite set to use: grows with wealth, not with age. */
    public enum Stage { SAPLING, YOUNG, MATURE }
}
