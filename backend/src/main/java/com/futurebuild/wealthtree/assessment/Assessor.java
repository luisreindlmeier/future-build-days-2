package com.futurebuild.wealthtree.assessment;

import com.futurebuild.wealthtree.model.AssetClass;
import com.futurebuild.wealthtree.model.Holding;
import com.futurebuild.wealthtree.model.SavingsCategory;
import com.futurebuild.wealthtree.model.SavingsPot;
import com.futurebuild.wealthtree.model.SpendingCategory;
import com.futurebuild.wealthtree.model.Transaction;
import com.futurebuild.wealthtree.model.UserData;
import com.futurebuild.wealthtree.model.UserProfile;

import java.time.YearMonth;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;

/**
 * Deterministic assessment: combines data inputs (pots, holdings, transactions)
 * with interpreted non-deterministic inputs (situation, risk, age).
 * All thresholds are explicit constants so the jury can see the methodology.
 */
public class Assessor {

    static final double BUFFER_TARGET_MONTHS = 6.0;     // 3 = minimum, 6 = healthy
    static final double SAVINGS_RATE_TARGET = 0.20;     // 50/30/20 guideline
    static final double WANTS_GUIDELINE = 0.30;
    static final double CONCENTRATION_LIMIT = 0.30;      // single position > 30% = concentrated
    static final double HEALTHY_FACTOR = 1.25;           // up to 25% above the peer average = still healthy
    static final double ROTTEN_FACTOR = 1.75;            // more than 75% above the peer average = rotten

    private final SituationInterpreter interpreter;

    public Assessor(SituationInterpreter interpreter) {
        this.interpreter = interpreter;
    }

    public Assessment assess(UserData d) {
        UserProfile p = d.profile();
        double income = p.netMonthlyIncome();
        List<String> findings = new ArrayList<>();

        // ---- Spending (leaves) ------------------------------------------------
        Map<YearMonth, List<Transaction>> byMonth = d.transactions().stream()
                .collect(Collectors.groupingBy(t -> YearMonth.from(t.date()), TreeMap::new, Collectors.toList()));
        int months = Math.max(1, byMonth.size());
        List<YearMonth> monthKeys = new ArrayList<>(byMonth.keySet());

        Map<SpendingCategory, Double> avgByCat = new EnumMap<>(SpendingCategory.class);
        for (SpendingCategory c : SpendingCategory.values()) {
            double total = d.transactions().stream().filter(t -> t.category() == c).mapToDouble(Transaction::amount).sum();
            if (total > 0) avgByCat.put(c, total / months);
        }
        double monthlySpend = avgByCat.values().stream().mapToDouble(Double::doubleValue).sum();
        double wants = avgByCat.entrySet().stream().filter(e -> !e.getKey().essential).mapToDouble(Map.Entry::getValue).sum();
        double wantsShare = income > 0 ? wants / income : 0;
        double savingsRate = income > 0 ? (income - monthlySpend) / income : 0;

        List<SpendingHabit> habits = new ArrayList<>();
        double weightedHealth = 0, weightSum = 0;
        for (Map.Entry<SpendingCategory, Double> e : avgByCat.entrySet()) {
            SpendingCategory c = e.getKey();
            double avg = e.getValue();
            double peer = SpendingBenchmarks.peerAverage(c, income);
            double budget = HEALTHY_FACTOR * peer;
            double trend = trend(byMonth, monthKeys, c);
            double ratio = peer > 0 ? avg / peer : 0;
            String vsPeers = ratio >= 1.05 ? String.format("%.1f× what households with your income spend (€%,.0f)", ratio, peer)
                    : ratio <= 0.95 ? String.format("below the €%,.0f households with your income spend", peer)
                    : String.format("about what households with your income spend (€%,.0f)", peer);
            String growing = trend > 0.05 ? String.format(", up %.0f%%", trend * 100) : "";
            HabitHealth h;
            if (!c.essential && (ratio > ROTTEN_FACTOR || (ratio > HEALTHY_FACTOR && trend >= 0.40))) h = HabitHealth.ROTTEN;
            else if (ratio > HEALTHY_FACTOR || trend >= 0.25) h = HabitHealth.WILTING;   // essentials (rent, food) can only wilt
            else h = HabitHealth.HEALTHY;
            String reason = vsPeers + growing;
            habits.add(new SpendingHabit(c, round(avg), round(budget), round(peer), SpendingBenchmarks.peerGroup(income),
                    round2(trend), h, reason));
            double hv = switch (h) { case HEALTHY -> 1.0; case WILTING -> 0.5; case ROTTEN -> 0.0; };
            if (!c.essential) { weightedHealth += hv * avg; weightSum += avg; }
            if (h == HabitHealth.ROTTEN) findings.add(c.label + ": " + reason + ".");
        }
        double leafHealth = weightSum > 0 ? weightedHealth / weightSum : 1;
        double wantsBalance = 1 - clamp((wantsShare - WANTS_GUIDELINE) / WANTS_GUIDELINE);
        int spendScore = pct(0.5 * wantsBalance + 0.5 * leafHealth);

        // ---- Savings (roots) --------------------------------------------------
        double emergency = sumPots(d.pots(), SavingsCategory.EMERGENCY);
        double bufferMonths = monthlySpend > 0 ? emergency / monthlySpend : 0;
        double goalsFunding = d.projects().isEmpty() ? 1
                : d.projects().stream().mapToDouble(x -> x.progress()).average().orElse(1);
        boolean hasProtection = d.pots().stream().anyMatch(x -> x.category() == SavingsCategory.PROTECTION);
        int savingsScore = pct(0.45 * clamp(bufferMonths / BUFFER_TARGET_MONTHS)
                + 0.30 * clamp(savingsRate / SAVINGS_RATE_TARGET)
                + 0.15 * goalsFunding
                + 0.10 * (hasProtection ? 1 : 0));
        if (bufferMonths < 3) findings.add(String.format("Emergency buffer covers %.1f months (healthy: 3–6).", bufferMonths));
        if (!hasProtection) findings.add("No protection against loss of income.");

        // ---- Investing (trunk) ------------------------------------------------
        double totalHoldings = d.holdings().stream().mapToDouble(Holding::value).sum();
        double idleCash = d.holdings().stream().filter(h -> h.assetClass() == AssetClass.CASH).mapToDouble(Holding::value).sum();
        double invested = totalHoldings - idleCash;
        double investedShare = totalHoldings > 0 ? invested / totalHoldings : 0;
        double largest = d.holdings().stream().filter(h -> h.assetClass() != AssetClass.CASH)
                .mapToDouble(Holding::value).max().orElse(0);
        double largestShare = invested > 0 ? largest / invested : 0;
        double hhi = invested > 0 ? d.holdings().stream().filter(h -> h.assetClass() != AssetClass.CASH)
                .mapToDouble(h -> Math.pow(h.value() / invested, 2)).sum() : 1;
        boolean onlyFunds = d.holdings().stream().filter(h -> h.assetClass() != AssetClass.CASH)
                .allMatch(h -> h.assetClass() == AssetClass.EQUITY_FUND || h.assetClass() == AssetClass.BOND_FUND);
        // A broad fund is diversified internally, so don't punish one big fund like one big stock.
        double diversification = invested <= 0 ? 0 : (onlyFunds ? Math.max(0.8, 1 - hhi) : 1 - hhi);
        double consistency = p.monthsInvestedLast12() / 12.0;
        int investScore = invested <= 0 && totalHoldings <= 0 ? 0
                : pct(0.35 * investedShare + 0.35 * clamp(diversification / 0.8) + 0.30 * consistency);
        if (idleCash > 3 * monthlySpend && investedShare < 0.6) findings.add(String.format("€%,.0f sits idle as cash.", idleCash));
        if (largestShare > CONCENTRATION_LIMIT && !onlyFunds) findings.add(String.format("%.0f%% of your investments are in one position.", largestShare * 100));

        // ---- Knowledge (soil) -------------------------------------------------
        int knowledgeScore = pct(clamp(p.knowledgeScore() + 0.05 * p.completedTrainings().size()));

        int overall = (int) Math.round(0.30 * savingsScore + 0.30 * investScore + 0.25 * spendScore + 0.15 * knowledgeScore);

        return new Assessment(p.id(), overall, savingsScore, investScore, spendScore, knowledgeScore,
                round(monthlySpend), round2(savingsRate), round2(bufferMonths), round2(wantsShare),
                round2(investedShare), round2(diversification), round2(largestShare), round(idleCash),
                avgByCat, habits, interpreter.interpret(p), findings);
    }

    private static double trend(Map<YearMonth, List<Transaction>> byMonth, List<YearMonth> keys, SpendingCategory c) {
        if (keys.size() < 4) return 0;
        int n = Math.min(3, keys.size() / 2);
        double first = 0, last = 0;
        for (int i = 0; i < n; i++) {
            first += sum(byMonth.get(keys.get(i)), c);
            last += sum(byMonth.get(keys.get(keys.size() - 1 - i)), c);
        }
        return first > 0 ? (last - first) / first : 0;
    }

    private static double sum(List<Transaction> list, SpendingCategory c) {
        return list.stream().filter(t -> t.category() == c).mapToDouble(Transaction::amount).sum();
    }

    static double sumPots(List<SavingsPot> pots, SavingsCategory c) {
        return pots.stream().filter(x -> x.category() == c).mapToDouble(SavingsPot::balance).sum();
    }

    static double clamp(double v) { return Math.max(0, Math.min(1, v)); }
    static int pct(double v) { return (int) Math.round(clamp(v) * 100); }
    static double round(double v) { return Math.round(v); }
    static double round2(double v) { return Math.round(v * 100) / 100.0; }
}
