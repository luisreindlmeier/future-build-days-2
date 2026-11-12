package com.futurebuild.wealthtree.model;


/** Self-declared risk appetite (non-deterministic input). */
public enum RiskTolerance {
    CAUTIOUS(0.03, 0.10),
    BALANCED(0.05, 0.20),
    GROWTH(0.065, 0.30);

    /** Illustrative expected yearly return used for projections. */
    public final double expectedReturn;
    /** Illustrative drop in a bad year, used by the storm test. */
    public final double badYearDrop;

    RiskTolerance(double expectedReturn, double badYearDrop) {
        this.expectedReturn = expectedReturn;
        this.badYearDrop = badYearDrop;
    }
}
