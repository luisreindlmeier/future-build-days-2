package com.futurebuild.wealthtree.tree;

/**
 * Investments. rings = years of consistent investing, cracks = structural risks (e.g. concentration, debt stress),
 * barkHealth = debt management from the scanner (0..1, null if not scanned).
 */
public record Trunk(double thickness, double height, int rings, int cracks, double stability, Double barkHealth,
                    PartStatus status, double invested, double idleCash, String detail) {}
