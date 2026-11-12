package com.futurebuild.wealthtree.model;


/** A savings account or pot. target may be 0 when there is no explicit target. */
public record SavingsPot(String id, SavingsCategory category, String name, double balance, double target) implements java.io.Serializable {
    public SavingsPot withBalance(double newBalance) {
        return new SavingsPot(id, category, name, newBalance, target);
    }
}
