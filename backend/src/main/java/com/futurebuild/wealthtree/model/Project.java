package com.futurebuild.wealthtree.model;


import java.time.LocalDate;

/** A personal project (house, travel, studies...). Becomes a branch of the tree. */
public record Project(String id, String name, String type, double targetAmount, double savedAmount, LocalDate targetDate) implements java.io.Serializable {
    public double progress() {
        return targetAmount <= 0 ? 1 : Math.min(1, savedAmount / targetAmount);
    }

    public Project withSaved(double saved) {
        return new Project(id, name, type, targetAmount, saved, targetDate);
    }
}
