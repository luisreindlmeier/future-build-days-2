package com.futurebuild.wealthtree.tree;

import com.futurebuild.wealthtree.model.SavingsCategory;

/** One root type per savings category. depth/thickness/health are 0..1 for the renderer. */
public record Root(SavingsCategory category, String label, double depth, double thickness, double health,
                   PartStatus status, double balance, double target, String detail) {}
