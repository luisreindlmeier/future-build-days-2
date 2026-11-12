package com.futurebuild.wealthtree.assessment;

public enum LifeStage {
    STARTER, BUILDER, ESTABLISHED;

    public static LifeStage ofAge(int age) {
        if (age < 26) return STARTER;
        if (age < 36) return BUILDER;
        return ESTABLISHED;
    }
}
