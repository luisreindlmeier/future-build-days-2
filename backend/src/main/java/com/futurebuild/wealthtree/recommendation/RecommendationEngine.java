package com.futurebuild.wealthtree.recommendation;

import com.futurebuild.wealthtree.assessment.Assessment;
import com.futurebuild.wealthtree.assessment.HabitHealth;
import com.futurebuild.wealthtree.assessment.SituationFlag;
import com.futurebuild.wealthtree.assessment.SpendingHabit;
import com.futurebuild.wealthtree.model.Project;
import com.futurebuild.wealthtree.model.SavingsCategory;
import com.futurebuild.wealthtree.model.SavingsPot;
import com.futurebuild.wealthtree.model.UserData;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import static com.futurebuild.wealthtree.recommendation.Catalog.product;
import static com.futurebuild.wealthtree.recommendation.Catalog.training;

/**
 * Rule-based recommendations: assessment + context -> actions (DB products) + knowledge trainings.
 * Every number in a recommendation is computed here; an LLM may only rephrase the "why".
 */
public class RecommendationEngine {

    public List<Recommendation> recommend(UserData d, Assessment a) {
        List<Recommendation> out = new ArrayList<>();
        double spend = a.monthlySpend();
        double freeCashFlow = Math.max(0, d.profile().netMonthlyIncome() - spend);
        double emergency = d.pots().stream().filter(p -> p.category() == SavingsCategory.EMERGENCY).mapToDouble(SavingsPot::balance).sum();
        double bufferGap = Math.max(0, 3 * spend - emergency);
        boolean firstSalary = a.context().has(SituationFlag.FIRST_SALARY);

        // ROOTS: emergency buffer
        if (a.bufferMonths() < 3) {
            if (a.idleCash() >= bufferGap && bufferGap > 0) {
                out.add(rec("rec-buffer", Pillar.ROOTS, 95, "Grow your safety roots",
                        String.format("Your buffer covers %.1f months. Move €%,.0f of idle cash into a safety pot to reach 3 months today.", a.bufferMonths(), bufferGap),
                        new Action("act-buffer", ActionType.MOVE_CASH, "Move €" + fmt(bufferGap) + " to your safety pot", SavingsCategory.EMERGENCY.name(), 0, round50(bufferGap), product("SAVINGS_ACCOUNT")),
                        training("buffer"), 8));
            } else {
                double monthly = Math.max(50, round50(Math.min(bufferGap / 12, 0.5 * freeCashFlow)));
                out.add(rec("rec-buffer", Pillar.ROOTS, 95, "Grow your safety roots",
                        String.format("Your buffer covers %.1f months (healthy: 3–6). €%,.0f on every payday closes the gap in about %d months.", a.bufferMonths(), monthly, (int) Math.ceil(bufferGap / monthly)),
                        new Action("act-buffer", ActionType.AUTO_SAVE, "Auto-save €" + fmt(monthly) + " on payday", SavingsCategory.EMERGENCY.name(), monthly, 0, product("SAVINGS_ACCOUNT")),
                        training(firstSalary ? "pay-yourself-first" : "buffer"), 8));
            }
        }

        // LEAVES: spending habits
        a.habits().stream()
                .filter(h -> !h.category().essential && h.health() != HabitHealth.HEALTHY)
                .sorted(Comparator.comparingDouble((SpendingHabit h) -> h.monthlyAverage() - h.monthlyBudget()).reversed())
                .limit(2)
                .forEach(h -> {
                    double limit = round50(Math.max(h.monthlyBudget(), h.monthlyAverage() * 0.75));
                    double freed = Math.max(0, h.monthlyAverage() - limit);
                    boolean rotten = h.health() == HabitHealth.ROTTEN;
                    out.add(rec("rec-limit-" + h.category().name().toLowerCase(), Pillar.LEAVES, rotten ? 85 : 60,
                            (rotten ? "Heal your " : "Trim your ") + h.category().label.toLowerCase() + " leaves",
                            String.format("%s averages €%,.0f a month: %s. A €%,.0f limit frees €%,.0f a month without cutting it out.",
                                    h.category().label, h.monthlyAverage(), h.reason(), limit, freed),
                            new Action("act-limit-" + h.category().name().toLowerCase(), ActionType.SPENDING_LIMIT,
                                    "Set a €" + fmt(limit) + " monthly limit for " + h.category().label.toLowerCase(),
                                    h.category().name(), limit, 0, product("BUDGET_ALERTS")),
                            training("spending"), rotten ? 6 : 3));
                });

        // BRANCH: projects. Fund from idle cash first (e.g. an inheritance), otherwise from monthly cash flow.
        double cashLeft = Math.max(0, a.idleCash() - bufferGap);
        for (Project pr : d.projects()) {
            if (pr.progress() >= 1) continue;
            double missing = pr.targetAmount() - pr.savedAmount();
            if (cashLeft >= missing) {
                cashLeft -= missing;
                out.add(rec("rec-project-" + pr.id(), Pillar.BRANCH, 70, "Fund your “" + pr.name() + "” branch today",
                        String.format("You already have the money: set aside €%,.0f of idle cash in a goal pot so it’s safe and ready for %s.", missing, pr.targetDate()),
                        new Action("act-project-" + pr.id(), ActionType.MOVE_CASH, "Move €" + fmt(missing) + " into “" + pr.name() + "”", pr.id(), 0, missing, product("GOAL_POT")),
                        training("goals"), 4));
            } else if (pr.targetDate() != null) {
                long monthsLeft = Math.max(1, ChronoUnit.MONTHS.between(LocalDate.now(), pr.targetDate()));
                double needed = round50(missing / monthsLeft);
                double affordable = Math.max(50, round50(0.4 * freeCashFlow));
                double monthly = Math.min(needed, affordable);
                String why = monthly >= needed
                        ? String.format("%.0f%% funded. €%,.0f a month gets you there by %s.", pr.progress() * 100, monthly, pr.targetDate())
                        : String.format("%.0f%% funded. You’d need €%,.0f a month to make %s; €%,.0f is realistic, so consider a later date or a smaller target.", pr.progress() * 100, needed, pr.targetDate(), monthly);
                out.add(rec("rec-project-" + pr.id(), Pillar.BRANCH, 45, "Grow your “" + pr.name() + "” branch", why,
                        new Action("act-project-" + pr.id(), ActionType.AUTO_SAVE, "Auto-save €" + fmt(monthly) + " into “" + pr.name() + "”", pr.id(), monthly, 0, product("GOAL_POT")),
                        training("goals"), 3));
            }
        }

        // TRUNK: idle cash
        double investable = cashLeft;
        if (investable > 3 * spend) {
            boolean large = investable >= 50_000;
            double monthly = round50(investable / 12);
            out.add(rec("rec-invest-idle", Pillar.TRUNK, 80, "Put idle money to work",
                    String.format("€%,.0f sits idle and loses value to inflation. Invest it in 12 monthly steps, %s, so a market drop never hits everything at once.",
                            investable, a.context().risk().name().toLowerCase()),
                    new Action("act-invest-idle", ActionType.INVEST_MONTHLY, "Invest €" + fmt(monthly) + " a month for 12 months",
                            a.context().risk().name(), monthly, 0, product(large ? "MANAGED_PORTFOLIO" : "FUND_SAVINGS_PLAN")),
                    training("stay-invested"), 10));
        }

        // TRUNK: concentration
        if (a.largestPositionShare() > 0.30 && a.diversification() < 0.6) {
            double invested = d.holdings().stream().filter(h -> h.assetClass() != com.futurebuild.wealthtree.model.AssetClass.CASH)
                    .mapToDouble(h -> h.value()).sum();
            // A family company is reduced step by step to 60% (as agreed at the family table); anything else to 30%.
            double targetShare = a.context().has(SituationFlag.FAMILY_BUSINESS) ? 0.60 : 0.30;
            double move = round50(Math.max(0, a.largestPositionShare() - targetShare) * invested);
            out.add(rec("rec-diversify", Pillar.TRUNK, 75, "Strengthen your trunk",
                    String.format("%.0f%% of your investments sit in one position. Spreading €%,.0f step by step (down to %.0f%%) reduces the risk of one bad year breaking the trunk.", a.largestPositionShare() * 100, move, targetShare * 100),
                    new Action("act-diversify", ActionType.DIVERSIFY, "Diversify €" + fmt(move) + " (tax-aware, with your RM)", "LARGEST_POSITION", 0, move, product("MANAGED_PORTFOLIO")),
                    training("diversification"), 6));
        }

        // TRUNK: consistency
        if (d.profile().monthsInvestedLast12() < 10 && freeCashFlow > 100 && investable <= 3 * spend) {
            double monthly = Math.max(50, round50(0.3 * freeCashFlow));
            out.add(rec("rec-savings-plan", Pillar.TRUNK, 55, "Add a ring every year",
                    String.format("You invested in %d of the last 12 months. A €%,.0f monthly savings plan builds consistency automatically.", d.profile().monthsInvestedLast12(), monthly),
                    new Action("act-savings-plan", ActionType.INVEST_MONTHLY, "Start a €" + fmt(monthly) + " monthly savings plan", d.profile().riskTolerance().name(), monthly, 0, product("FUND_SAVINGS_PLAN")),
                    training("diversification"), 5));
        }

        // ROOTS: protection and retirement
        if (d.pots().stream().noneMatch(p -> p.category() == SavingsCategory.PROTECTION)) {
            out.add(rec("rec-protect", Pillar.ROOTS, 50, "Anchor your tree",
                    "Your income is your biggest asset and it isn’t protected. Disability cover keeps the tree standing if you can’t work.",
                    new Action("act-protect", ActionType.PROTECT, "Check disability cover", SavingsCategory.PROTECTION.name(), 0, 0, product("DISABILITY_INSURANCE")),
                    training("protection"), 3));
        }
        if (d.profile().age() >= 25 && d.pots().stream().noneMatch(p -> p.category() == SavingsCategory.RETIREMENT)) {
            out.add(rec("rec-retirement", Pillar.ROOTS, 35, "Grow your deep roots",
                    "Starting retirement saving early does most of the work for you through compounding.",
                    new Action("act-retirement", ActionType.AUTO_SAVE, "Start a €100 monthly pension plan", SavingsCategory.RETIREMENT.name(), 100, 0, product("RETIREMENT_PLAN")),
                    training("retirement"), 2));
        }

        // SOIL: knowledge
        if (a.knowledgeScore() < 60) {
            out.add(rec("rec-learn", Pillar.SOIL, 40, "Enrich your soil",
                    "Short learning steps make every other decision easier. Start with the module that matches your next action.",
                    new Action("act-learn", ActionType.LEARN, "Complete a 5-minute module", "KNOWLEDGE", 0, 0, null),
                    training(a.investScore() < 50 ? "diversification" : "spending"), 2));
        }

        // Situation-specific (non-deterministic inputs)
        if (a.context().has(SituationFlag.INHERITANCE)) {
            out.add(rec("rec-inheritance", Pillar.ROOTS, 90, "Give your inheritance a structure",
                    "Before big decisions: complete the checklist (certificate, asset list, tax notification) and plan it with your Relationship Manager.",
                    new Action("act-inheritance", ActionType.ADVISOR_MEETING, "Book an inheritance debrief", "INHERITANCE", 0, 0, product("RM_MEETING")),
                    training("inheritance"), 4));
        }
        if (a.context().has(SituationFlag.VARIABLE_INCOME) || a.context().has(SituationFlag.STARTING_BUSINESS)) {
            out.add(rec("rec-separate", Pillar.ROOTS, 88, "Separate business and personal roots",
                    "Mixed accounts hide what your life really costs. Separate them and pay yourself a fixed monthly salary.",
                    new Action("act-separate", ActionType.SEPARATE_ACCOUNTS, "Open a business account and set an owner’s salary", "BUSINESS", 0, 0, product("BUSINESS_ACCOUNT")),
                    training("founder"), 5));
        }

        out.sort(Comparator.comparingInt(Recommendation::priority).reversed());
        return out;
    }

    private static Recommendation rec(String id, Pillar pillar, int prio, String title, String why, Action action, Training t, int gain) {
        return new Recommendation(id, pillar, prio, title, why, action, t, gain, null);
    }

    static double round50(double v) { return Math.max(0, Math.round(v / 50.0) * 50.0); }
    static String fmt(double v) { return String.format("%,.0f", v); }
}
