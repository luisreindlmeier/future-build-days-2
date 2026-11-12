package com.futurebuild.wealthtree.tree;

import com.futurebuild.wealthtree.assessment.HabitHealth;
import com.futurebuild.wealthtree.model.SpendingCategory;

/** One cluster per spending category. size scales with spending; rottenRatio = share of bad leaves. */
public record LeafCluster(SpendingCategory category, String label, boolean essential, double size, int leafCount,
                          HabitHealth health, double rottenRatio, double monthlyAmount, double monthlyBudget,
                          double peerAverage, String peerGroup,
                          double trendPct, String detail) {}
