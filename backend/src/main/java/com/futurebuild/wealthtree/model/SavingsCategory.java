package com.futurebuild.wealthtree.model;


/** Each savings category becomes its own root type in the tree. */
public enum SavingsCategory {
    EMERGENCY("Safety roots", "Emergency buffer"),
    GOALS("Goal roots", "Savings for projects"),
    RETIREMENT("Deep roots", "Retirement provision"),
    PROTECTION("Anchor roots", "Insurance and protection");

    public final String treeLabel;
    public final String description;

    SavingsCategory(String treeLabel, String description) {
        this.treeLabel = treeLabel;
        this.description = description;
    }
}
