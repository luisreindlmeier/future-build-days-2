package com.futurebuild.wealthtree.profiles;

import com.futurebuild.wealthtree.model.RiskTolerance;
import com.futurebuild.wealthtree.model.SpendingCategory;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Everything a customer tells us when they create or personalise their own profile. One flat form,
 * so the UI can be a simple wizard. Amounts in EUR, monthly unless stated. validated() checks every
 * field and returns a normalised copy, or throws IllegalArgumentException (HTTP 400) with a readable message.
 */
public record ProfileRequest(
        String name,
        Integer age,
        String lifeStage,              // pro | founder | heir
        String purpose,                // what the money is for, in the customer's words
        String situation,              // free text, read by the situation interpreter
        String riskTolerance,          // CAUTIOUS | BALANCED | GROWTH
        Double monthlyIncome,          // net
        String incomeNote,
        Map<String, Double> spending,  // SpendingCategory name -> EUR per month
        Double cashSavings,            // savings account / buffer
        Double investments,            // funds, ETFs, pension plans
        Double companyShares,          // a single company (family company, own start-up, employer shares)
        Double monthlySavingCash,      // negative = spends more than earns
        Double monthlySavingInvested,
        String crashReaction,          // sell | hold | buy  (reflex test: markets fall 30%)
        Boolean disabilityCover,
        Boolean will,
        Integer confidence,            // 1..5  "I feel on top of my money"
        Integer knowledge,             // 1..7  self-assessed financial knowledge
        Integer shockAbsorb,           // 1..4  could you handle an unexpected €2,000 bill?
        Integer horizonYears,
        List<Goal> goals,
        List<Subscription> subscriptions,
        List<Purchase> plannedPurchases
) {
    public record Goal(String type, Double target, Integer years, Integer priority) {}
    public record Subscription(String name, Double monthly, Integer lastUsedDays) {}
    public record Purchase(String label, Double amount, Integer inMonths) {}

    private static final Set<String> STAGES = Set.of("pro", "founder", "heir");
    private static final Set<String> CRASH = Set.of("sell", "hold", "buy");
    private static final Set<String> GOAL_TYPES = Set.of("wealth", "home", "keep");

    public ProfileRequest validated() {
        String n = text(name, "name", 1, 40);
        int a = whole(age, "age", 18, 85);
        String stage = pick(lifeStage, "lifeStage", STAGES, "pro");
        RiskTolerance risk;
        try {
            risk = RiskTolerance.valueOf(riskTolerance == null ? "BALANCED" : riskTolerance.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("riskTolerance must be CAUTIOUS, BALANCED or GROWTH.");
        }
        double income = amount(monthlyIncome, "monthlyIncome", 300, 200_000);
        Map<String, Double> sp = new LinkedHashMap<>();
        if (spending != null) {
            for (Map.Entry<String, Double> e : spending.entrySet()) {
                SpendingCategory c;
                try {
                    c = SpendingCategory.valueOf(e.getKey().trim().toUpperCase(Locale.ROOT));
                } catch (IllegalArgumentException ex) {
                    throw new IllegalArgumentException("Unknown spending category: " + e.getKey());
                }
                double v = amount(e.getValue(), "spending." + c.name(), 0, 100_000);
                if (v > 0) sp.put(c.name(), v);
            }
        }
        if (sp.isEmpty()) throw new IllegalArgumentException("Add at least one spending category (for example housing).");
        int horizon = whole(horizonYears == null ? 15 : horizonYears, "horizonYears", 3, 30);
        List<Goal> gs = new ArrayList<>();
        if (goals == null || goals.isEmpty() || goals.size() > 2) throw new IllegalArgumentException("Add one or two goals.");
        int prio = 1;
        for (Goal g : goals) {
            String t = pick(g.type(), "goal type", GOAL_TYPES, null);
            Double target = t.equals("keep") ? null : amount(g.target(), "goal target", 1_000, 100_000_000);
            Integer years = t.equals("home") ? whole(g.years(), "home goal years", 1, horizon) : null;
            gs.add(new Goal(t, target, years, prio++));
        }
        List<Subscription> subs = new ArrayList<>();
        if (subscriptions != null) {
            if (subscriptions.size() > 10) throw new IllegalArgumentException("At most 10 subscriptions.");
            for (Subscription s : subscriptions) {
                if (s == null || s.name() == null || s.name().isBlank()) continue;
                subs.add(new Subscription(text(s.name(), "subscription name", 1, 40), amount(s.monthly(), "subscription amount", 0, 5_000),
                        whole(s.lastUsedDays() == null ? 0 : s.lastUsedDays(), "days since last use", 0, 3650)));
            }
        }
        List<Purchase> ps = new ArrayList<>();
        if (plannedPurchases != null) {
            if (plannedPurchases.size() > 3) throw new IllegalArgumentException("At most 3 planned purchases.");
            for (Purchase p : plannedPurchases) {
                if (p == null || p.label() == null || p.label().isBlank()) continue;
                ps.add(new Purchase(text(p.label(), "purchase", 1, 40), amount(p.amount(), "purchase amount", 0, 10_000_000),
                        whole(p.inMonths() == null ? 6 : p.inMonths(), "purchase months", 0, 60)));
            }
        }
        double spend = sp.values().stream().mapToDouble(Double::doubleValue).sum();
        double defaultSaving = Math.max(0, Math.round(income - spend));
        return new ProfileRequest(n, a, stage,
                optional(purpose, "purpose", 60, "Security"),
                optional(situation, "situation", 400, ""),
                risk.name(), income, optional(incomeNote, "incomeNote", 80, null), sp,
                amount(cashSavings == null ? 0.0 : cashSavings, "cashSavings", 0, 10_000_000),
                amount(investments == null ? 0.0 : investments, "investments", 0, 100_000_000),
                amount(companyShares == null ? 0.0 : companyShares, "companyShares", 0, 100_000_000),
                amount(monthlySavingCash == null ? defaultSaving : monthlySavingCash, "monthlySavingCash", -50_000, 50_000),
                amount(monthlySavingInvested == null ? 0.0 : monthlySavingInvested, "monthlySavingInvested", 0, 50_000),
                pick(crashReaction, "crashReaction", CRASH, "hold"),
                Boolean.TRUE.equals(disabilityCover), Boolean.TRUE.equals(will),
                whole(confidence == null ? 3 : confidence, "confidence", 1, 5),
                whole(knowledge == null ? 4 : knowledge, "knowledge", 1, 7),
                whole(shockAbsorb == null ? 2 : shockAbsorb, "shockAbsorb", 1, 4),
                horizon, List.copyOf(gs), List.copyOf(subs), List.copyOf(ps));
    }

    private static String text(String v, String field, int min, int max) {
        String t = v == null ? "" : v.strip();
        if (t.length() < min || t.length() > max) throw new IllegalArgumentException(field + " must be " + min + "–" + max + " characters.");
        return t;
    }

    private static String optional(String v, String field, int max, String fallback) {
        if (v == null || v.isBlank()) return fallback;
        return text(v, field, 1, max);
    }

    private static String pick(String v, String field, Set<String> allowed, String fallback) {
        if ((v == null || v.isBlank()) && fallback != null) return fallback;
        String t = v == null ? "" : v.trim().toLowerCase(Locale.ROOT);
        if (!allowed.contains(t)) throw new IllegalArgumentException(field + " must be one of " + allowed + ".");
        return t;
    }

    private static int whole(Integer v, String field, int min, int max) {
        if (v == null || v < min || v > max) throw new IllegalArgumentException(field + " must be between " + min + " and " + max + ".");
        return v;
    }

    private static double amount(Double v, String field, double min, double max) {
        if (v == null || v.isNaN() || v < min || v > max) {
            throw new IllegalArgumentException(field + " must be between " + (long) min + " and " + (long) max + ".");
        }
        return Math.round(v * 100) / 100.0;
    }
}
