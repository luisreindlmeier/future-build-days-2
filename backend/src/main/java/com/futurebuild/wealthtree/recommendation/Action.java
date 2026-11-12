package com.futurebuild.wealthtree.recommendation;

/**
 * A concrete step the user can commit to.
 * target = what it applies to (savings category, spending category, project id...).
 * monthlyAmount / oneOffAmount drive the projection.
 */
public record Action(
        String id,
        ActionType type,
        String title,
        String target,
        double monthlyAmount,
        double oneOffAmount,
        Product product
) {}
