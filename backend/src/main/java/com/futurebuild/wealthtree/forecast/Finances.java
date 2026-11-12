package com.futurebuild.wealthtree.forecast;

/**
 * Starting point of a customer.
 * cash = buffer cash (capped at potCap months, overflow is invested, as in the demo);
 * idle = extra uninvested cash that just earns cash interest (engine extension, 0 = demo behaviour).
 */
public record Finances(double total, double cash, double idle, double income, double spend) {}
