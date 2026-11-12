package com.futurebuild.wealthtree.projection;

import com.futurebuild.wealthtree.assessment.Assessment;
import com.futurebuild.wealthtree.assessment.Assessor;
import com.futurebuild.wealthtree.model.AssetClass;
import com.futurebuild.wealthtree.model.Holding;
import com.futurebuild.wealthtree.model.Project;
import com.futurebuild.wealthtree.model.SavingsCategory;
import com.futurebuild.wealthtree.model.SavingsPot;
import com.futurebuild.wealthtree.model.SpendingCategory;
import com.futurebuild.wealthtree.model.Transaction;
import com.futurebuild.wealthtree.model.UserData;
import com.futurebuild.wealthtree.model.UserProfile;
import com.futurebuild.wealthtree.recommendation.Action;
import com.futurebuild.wealthtree.recommendation.Recommendation;
import com.futurebuild.wealthtree.scanner.WellBeing;
import com.futurebuild.wealthtree.tree.TreeBuilder;
import com.futurebuild.wealthtree.tree.TreeState;

import java.time.YearMonth;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.function.BiFunction;
import java.util.stream.Collectors;

/**
 * Simple, explainable month-based simulation. It replays the user's recent spending pattern,
 * applies the committed actions and re-runs the same assessment and tree builder.
 */
public class ProjectionService {

    private final Assessor assessor;
    private final TreeBuilder treeBuilder;
    private BiFunction<String, List<Recommendation>, WellBeing> wellbeing = (id, recs) -> null;

    public ProjectionService(Assessor assessor, TreeBuilder treeBuilder) {
        this.assessor = assessor;
        this.treeBuilder = treeBuilder;
    }

    /** Lets the future tree use the scanner too: (userId, completed actions) -> scanner result. */
    public void setWellbeing(BiFunction<String, List<Recommendation>, WellBeing> f) {
        this.wellbeing = f;
    }

    public ProjectionResult project(UserData d, List<Recommendation> chosen, int months) {
        int before = assessor.assess(d).overallScore();
        TreeSet<Integer> checkpoints = new TreeSet<>(List.of(0, 3, 6, 12));
        checkpoints.add(months);
        List<TimelinePoint> timeline = new ArrayList<>();
        for (int m : checkpoints) {
            if (m > months) continue;
            Assessment a = assessor.assess(m == 0 ? d : simulate(d, chosen, m));
            timeline.add(new TimelinePoint(m, a.overallScore(), a.savingsScore(), a.investScore(), a.spendScore(), a.knowledgeScore()));
        }
        UserData future = simulate(d, chosen, months);
        Assessment after = assessor.assess(future);
        TreeState treeAfter = treeBuilder.build(future, after, wellbeing.apply(d.profile().id(), chosen));
        return new ProjectionResult(months, chosen.stream().map(r -> r.action().id()).toList(), before,
                after.overallScore(), after, treeAfter, timeline);
    }

    UserData simulate(UserData d, List<Recommendation> chosen, int months) {
        List<SavingsPot> pots = new ArrayList<>(d.pots());
        List<Holding> holdings = new ArrayList<>(d.holdings());
        List<Project> projects = new ArrayList<>(d.projects());
        Map<SpendingCategory, Double> limits = new EnumMap<>(SpendingCategory.class);
        UserProfile p = d.profile();
        double knowledge = p.knowledgeScore();
        List<String> trainings = new ArrayList<>(p.completedTrainings());
        int monthsInvested = p.monthsInvestedLast12();
        double yearly = p.riskTolerance().expectedReturn;

        for (Recommendation r : chosen) {
            Action ac = r.action();
            if (r.training() != null && !trainings.contains(r.training().id())) trainings.add(r.training().id());
            switch (ac.type()) {
                case AUTO_SAVE -> {
                    double total = ac.monthlyAmount() * months;
                    int pi = indexOfProject(projects, ac.target());
                    if (pi >= 0) projects.set(pi, projects.get(pi).withSaved(projects.get(pi).savedAmount() + total));
                    else addToPot(pots, SavingsCategory.valueOf(ac.target()), total);
                }
                case MOVE_CASH -> {
                    double moved = takeCash(holdings, ac.oneOffAmount());
                    int pi = indexOfProject(projects, ac.target());
                    if (pi >= 0) projects.set(pi, projects.get(pi).withSaved(projects.get(pi).savedAmount() + moved));
                    else addToPot(pots, SavingsCategory.valueOf(ac.target()), moved);
                }
                case SPENDING_LIMIT -> limits.put(SpendingCategory.valueOf(ac.target()), ac.monthlyAmount());
                case INVEST_MONTHLY -> {
                    double total = ac.monthlyAmount() * months;
                    double fromCash = takeCash(holdings, total);
                    double newMoney = r.id().equals("rec-invest-idle") ? fromCash : total;
                    double grown = newMoney * (1 + yearly * months / 24.0); // contributions are invested on average half the period
                    holdings.add(new Holding("Diversified portfolio (" + ac.target().toLowerCase() + ")", AssetClass.EQUITY_FUND, grown));
                    monthsInvested = Math.min(12, Math.max(monthsInvested, months));
                }
                case DIVERSIFY -> {
                    holdings.stream().filter(h -> h.assetClass() != AssetClass.CASH)
                            .max((x, y) -> Double.compare(x.value(), y.value()))
                            .ifPresent(h -> {
                                double move = Math.min(h.value(), ac.oneOffAmount());
                                holdings.set(holdings.indexOf(h), h.withValue(h.value() - move));
                                holdings.add(new Holding("Diversified fund", AssetClass.EQUITY_FUND, move));
                            });
                }
                case PROTECT -> {
                    if (pots.stream().noneMatch(x -> x.category() == SavingsCategory.PROTECTION))
                        pots.add(new SavingsPot("pot-protection", SavingsCategory.PROTECTION, "Disability cover", 0, 1));
                }
                case LEARN, ADVISOR_MEETING -> knowledge = Math.min(1, knowledge + 0.15);
                case SEPARATE_ACCOUNTS -> { /* structural change, shows via training and weather follow-up */ }
            }
        }
        // Existing investments grow with the expected return of the risk profile.
        for (int i = 0; i < holdings.size(); i++) {
            Holding h = holdings.get(i);
            if (h.assetClass() != AssetClass.CASH && !h.name().startsWith("Diversified portfolio"))
                holdings.set(i, h.withValue(h.value() * Math.pow(1 + yearly, months / 12.0)));
        }
        int years = p.yearsConsistent() + (monthsInvested >= 12 && months >= 12 ? months / 12 : 0);
        UserProfile fp = p.withProgress(knowledge, List.copyOf(trainings), monthsInvested, years);
        return new UserData(fp, List.copyOf(pots), List.copyOf(holdings), futureSpending(d.transactions(), limits), List.copyOf(projects));
    }

    /** Replays the last 3 months twice (6 months of data), capping limited categories. */
    static List<Transaction> futureSpending(List<Transaction> tx, Map<SpendingCategory, Double> limits) {
        Map<YearMonth, List<Transaction>> byMonth = tx.stream().collect(Collectors.groupingBy(t -> YearMonth.from(t.date())));
        List<YearMonth> recent = byMonth.keySet().stream().sorted().toList();
        recent = recent.subList(Math.max(0, recent.size() - 3), recent.size());
        List<Transaction> out = new ArrayList<>();
        YearMonth start = YearMonth.now().plusMonths(1);
        for (int k = 0; k < 6 && !recent.isEmpty(); k++) {
            YearMonth src = recent.get(k % recent.size());
            YearMonth dst = start.plusMonths(k);
            Map<SpendingCategory, Double> totals = byMonth.get(src).stream()
                    .collect(Collectors.groupingBy(Transaction::category, Collectors.summingDouble(Transaction::amount)));
            for (Transaction t : byMonth.get(src)) {
                double factor = 1;
                Double limit = limits.get(t.category());
                if (limit != null && totals.get(t.category()) > limit) factor = limit / totals.get(t.category());
                int day = Math.min(t.date().getDayOfMonth(), dst.lengthOfMonth());
                out.add(new Transaction(dst.atDay(day), t.category(), t.amount() * factor, t.description()));
            }
        }
        return out;
    }

    private static double takeCash(List<Holding> holdings, double amount) {
        double taken = 0;
        for (int i = 0; i < holdings.size() && taken < amount; i++) {
            Holding h = holdings.get(i);
            if (h.assetClass() != AssetClass.CASH) continue;
            double t = Math.min(h.value(), amount - taken);
            holdings.set(i, h.withValue(h.value() - t));
            taken += t;
        }
        return taken;
    }

    private static void addToPot(List<SavingsPot> pots, SavingsCategory c, double amount) {
        for (int i = 0; i < pots.size(); i++) {
            if (pots.get(i).category() == c) {
                pots.set(i, pots.get(i).withBalance(pots.get(i).balance() + amount));
                return;
            }
        }
        pots.add(new SavingsPot("pot-" + c.name().toLowerCase(), c, c.description, amount, 0));
    }

    private static int indexOfProject(List<Project> projects, String id) {
        for (int i = 0; i < projects.size(); i++) if (projects.get(i).id().equals(id)) return i;
        return -1;
    }
}
