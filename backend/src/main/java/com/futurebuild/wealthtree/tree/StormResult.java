package com.futurebuild.wealthtree.tree;

/** Result of the storm (market crash) test, for the animation. */
public record StormResult(boolean recovers, double leanDegrees, double portfolioDrop, String message) {}
