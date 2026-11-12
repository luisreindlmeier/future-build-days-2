package com.futurebuild.wealthtree.forecast;

/**
 * Engine assumptions, identical to the team's checkup demo (ASSUME). Illustrative, not calibrated:
 * in production they come from the bank's capital-market assumptions.
 */
public record Assumptions(
        int paths, long seed,
        double coMu, double coSd,       // single company: mean return, volatility
        double mkMu, double mkSd,       // broad market
        double rho,                     // correlation company / market
        double cashR,                   // cash interest
        double pDis,                    // chance per year of a year without income
        double panicAt,                 // market fall that triggers a panic sale
        double glide, double floor,     // diversification: -11 points a year down to 60%
        double potCap,                  // buffer above 6 months of spending gets invested
        double coverRatio               // disability cover pays 60% of income
) {
    public static final Assumptions DEMO = new Assumptions(2000, 260841, 0.07, 0.30, 0.06, 0.15, 0.3,
            0.015, 0.004, -0.15, 0.11, 0.60, 6, 0.6);
}
