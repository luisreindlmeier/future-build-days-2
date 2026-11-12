package com.futurebuild.wealthtree.tree;

/** Calm status words shown instead of scores. */
public enum PartStatus { STRONG, GROWING, NEEDS_CARE, MISSING;
    public static PartStatus of(double v) { return v >= 0.75 ? STRONG : v >= 0.4 ? GROWING : NEEDS_CARE; }
}
