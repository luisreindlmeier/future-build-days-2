package com.futurebuild.wealthtree.recommendation;

import java.util.Map;

/** Product and training catalog. Replace names/urls with real Deutsche Bank offers. */
public final class Catalog {
    private Catalog() {}

    public static final Map<String, Product> PRODUCTS = Map.of(
            "SAVINGS_ACCOUNT", new Product("SAVINGS_ACCOUNT", "Instant-access savings account", "Save", null),
            "GOAL_POT", new Product("GOAL_POT", "Goal savings pot", "Save", null),
            "FUND_SAVINGS_PLAN", new Product("FUND_SAVINGS_PLAN", "Fund savings plan (monthly)", "Invest", null),
            "MANAGED_PORTFOLIO", new Product("MANAGED_PORTFOLIO", "Digital wealth management", "Invest", null),
            "RETIREMENT_PLAN", new Product("RETIREMENT_PLAN", "Private pension plan", "Save", null),
            "DISABILITY_INSURANCE", new Product("DISABILITY_INSURANCE", "Occupational disability insurance", "Protect", null),
            "BUDGET_ALERTS", new Product("BUDGET_ALERTS", "In-app budget limits and alerts", "Spend", null),
            "BUSINESS_ACCOUNT", new Product("BUSINESS_ACCOUNT", "Business account", "Business", null),
            "RM_MEETING", new Product("RM_MEETING", "Meeting with your Relationship Manager", "Advice", null)
    );

    public static final Map<String, Training> TRAININGS = Map.of(
            "buffer", new Training("buffer", "Why a safety buffer comes first", 4),
            "pay-yourself-first", new Training("pay-yourself-first", "Pay yourself first: automate saving", 3),
            "spending", new Training("spending", "Spending habits without guilt", 5),
            "diversification", new Training("diversification", "Diversification: don’t bet on one tree", 5),
            "stay-invested", new Training("stay-invested", "Storms pass: staying invested in a crash", 4),
            "protection", new Training("protection", "Protecting your income", 4),
            "inheritance", new Training("inheritance", "Your inheritance checklist", 6),
            "founder", new Training("founder", "Founder finances: separate and pay yourself", 6),
            "retirement", new Training("retirement", "Retirement basics in 5 minutes", 5),
            "goals", new Training("goals", "Turning a dream into a savings plan", 4)
    );

    public static Product product(String id) { return PRODUCTS.get(id); }
    public static Training training(String id) { return TRAININGS.get(id); }
}
