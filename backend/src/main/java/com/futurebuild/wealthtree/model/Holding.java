package com.futurebuild.wealthtree.model;


/** One position in the portfolio. CASH holdings count as idle money. */
public record Holding(String name, AssetClass assetClass, double value) implements java.io.Serializable {
    public Holding withValue(double newValue) {
        return new Holding(name, assetClass, newValue);
    }
}
