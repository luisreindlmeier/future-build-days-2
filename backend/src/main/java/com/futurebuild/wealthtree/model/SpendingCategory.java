package com.futurebuild.wealthtree.model;


/** Each spending category becomes a leaf cluster. Benchmarks: assessment/SpendingBenchmarks (Destatis). */
public enum SpendingCategory {
    HOUSING("Housing", true),
    GROCERIES("Groceries", true),
    TRANSPORT("Transport", true),
    EATING_OUT("Eating out", false),
    SHOPPING("Shopping", false),
    TRAVEL("Travel", false),
    SUBSCRIPTIONS("Subscriptions", false),
    OTHER("Other", false);

    public final String label;
    public final boolean essential;

    SpendingCategory(String label, boolean essential) {
        this.label = label;
        this.essential = essential;
    }
}
