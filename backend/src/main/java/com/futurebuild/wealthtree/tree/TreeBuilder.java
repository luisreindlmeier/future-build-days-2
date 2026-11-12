package com.futurebuild.wealthtree.tree;

import com.futurebuild.wealthtree.assessment.Assessment;
import com.futurebuild.wealthtree.assessment.HabitHealth;
import com.futurebuild.wealthtree.assessment.SituationFlag;
import com.futurebuild.wealthtree.assessment.SpendingHabit;
import com.futurebuild.wealthtree.model.AssetClass;
import com.futurebuild.wealthtree.model.Holding;
import com.futurebuild.wealthtree.model.Project;
import com.futurebuild.wealthtree.model.SavingsCategory;
import com.futurebuild.wealthtree.model.SavingsPot;
import com.futurebuild.wealthtree.model.UserData;
import com.futurebuild.wealthtree.scanner.WellBeing;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Turns data + assessment into the visual tree. No business rules here beyond mapping. */
public class TreeBuilder {

    public TreeState build(UserData d, Assessment a) {
        return build(d, a, null);
    }

    /**
     * With a scanner result the tree uses the validated CFPB dimensions where they fit:
     * reserves -> safety roots' health, planning_protection -> deep and anchor roots' health,
     * debt -> bark health (and a crack below 50), confidence_skill -> soil richness,
     * and overall health = 50% the client's CFPB percentile among peers of the same age + 50% the bank-data score.
     */
    public TreeState build(UserData d, Assessment a, WellBeing wb) {
        double income = d.profile().netMonthlyIncome();
        double spend = Math.max(1, a.monthlySpend());

        // Roots: one per savings category, always present so the renderer can show missing ones as stubs.
        List<Root> roots = new ArrayList<>();
        double projectSavings = d.projects().stream().mapToDouble(Project::savedAmount).sum();
        for (SavingsCategory c : SavingsCategory.values()) {
            double balance = d.pots().stream().filter(p -> p.category() == c).mapToDouble(SavingsPot::balance).sum()
                    + (c == SavingsCategory.GOALS ? projectSavings : 0);
            boolean present = d.pots().stream().anyMatch(p -> p.category() == c) || (c == SavingsCategory.GOALS && projectSavings > 0);
            double target = switch (c) {
                case EMERGENCY -> 6 * spend;
                case GOALS -> Math.max(1, d.projects().stream().mapToDouble(Project::targetAmount).sum());
                case RETIREMENT -> { double t = d.pots().stream().filter(p -> p.category() == c).mapToDouble(SavingsPot::target).sum(); yield t > 0 ? t : 24 * income; }
                case PROTECTION -> 1;
            };
            double depth = !present ? 0 : c == SavingsCategory.PROTECTION ? 0.8 : clamp(balance / target);
            PartStatus st = !present ? PartStatus.MISSING : PartStatus.of(depth);
            String detail = switch (c) {
                case EMERGENCY -> String.format("€%,.0f covers %.1f months of costs (healthy: 3–6).", balance, a.bufferMonths());
                case GOALS -> present ? String.format("€%,.0f saved towards your projects.", balance) : "No savings set aside for your projects yet.";
                case RETIREMENT -> present ? String.format("€%,.0f in retirement provision.", balance) : "No private retirement provision yet.";
                case PROTECTION -> present ? "Income protection in place." : "Your income isn’t protected yet.";
            };
            double health = depth;
            if (wb != null && present) {
                Double dim = c == SavingsCategory.EMERGENCY ? wb.dim("reserves")
                        : (c == SavingsCategory.RETIREMENT || c == SavingsCategory.PROTECTION) ? wb.dim("planning_protection") : null;
                if (dim != null) health = dim / 100.0;
            }
            // The money is there (scanner: healthy) but little sits in the safety pot itself (shallow root):
            // say so, instead of showing perfect health next to "needs care".
            if (c == SavingsCategory.EMERGENCY && health >= 0.75 && depth < 0.5) {
                st = PartStatus.GROWING;
                detail = String.format("Your savings could cover a shock, but only €%,.0f (%.1f months of costs) is set aside as a safety pot.",
                        balance, a.bufferMonths());
            }
            roots.add(new Root(c, c.treeLabel, r2(depth), r2(present ? 0.2 + 0.8 * depth : 0.05), r2(health), st, balance, target, detail));
        }

        // Trunk
        double invested = d.holdings().stream().filter(h -> h.assetClass() != AssetClass.CASH).mapToDouble(Holding::value).sum();
        int cracks = (a.largestPositionShare() > 0.30 && a.diversification() < 0.6 ? 1 : 0)
                + (d.profile().monthsInvestedLast12() < 3 && invested > 0 ? 1 : 0);
        Double debt = wb == null ? null : wb.dim("debt");
        if (debt != null && debt < 50) cracks++;
        double trunkVal = a.investScore() / 100.0;
        Trunk trunk = new Trunk(
                r2(0.15 + 0.85 * trunkVal),
                r2(0.3 + 0.7 * a.overallScore() / 100.0),
                d.profile().yearsConsistent(),
                cracks,
                r2(clamp(0.5 * a.diversification() + 0.5 * a.bufferMonths() / 6)),
                debt == null ? null : r2(debt / 100.0),
                PartStatus.of(trunkVal),
                invested, a.idleCash(),
                String.format("€%,.0f invested, %.0f%% of your investable money. €%,.0f idle in cash.", invested, a.investedShare() * 100, a.idleCash()));

        // Leaves: size scales with spending relative to income (sqrt to keep small categories visible).
        List<LeafCluster> leaves = new ArrayList<>();
        for (SpendingHabit h : a.habits()) {
            double size = clamp(Math.sqrt(h.monthlyAverage() / Math.max(1, income) / 0.35));
            double vsPeer = h.peerAverage() > 0 ? h.monthlyAverage() / h.peerAverage() : 1;
            double rotten = switch (h.health()) {
                case HEALTHY -> 0;
                case WILTING -> 0.25;
                case ROTTEN -> clamp(0.4 + 0.3 * (vsPeer - 1.75));
            };
            leaves.add(new LeafCluster(h.category(), h.category().label, h.category().essential, r2(size),
                    (int) Math.round(6 + 34 * size), h.health(), r2(rotten), h.monthlyAverage(), h.monthlyBudget(),
                    h.peerAverage(), h.peerGroup(), h.trendPct(), String.format("€%,.0f a month, %s.", h.monthlyAverage(), h.reason())));
        }
        leaves.sort(Comparator.comparingDouble(LeafCluster::size).reversed());

        // Branches: projects, spread evenly over the crown.
        List<Branch> branches = new ArrayList<>();
        int n = d.projects().size();
        for (int i = 0; i < n; i++) {
            Project p = d.projects().get(i);
            double angle = n == 1 ? -30 : -60 + 120.0 * i / (n - 1);
            branches.add(new Branch(p.id(), p.name(), p.type(), r2(0.2 + 0.8 * p.progress()), angle,
                    p.progress() >= 1, p.progress() >= 0.5 && p.progress() < 1,
                    String.format("€%,.0f of €%,.0f (%.0f%%).", p.savedAmount(), p.targetAmount(), p.progress() * 100)));
        }

        // Soil
        int trainings = d.profile().completedTrainings().size();
        Double conf = wb == null ? null : wb.dim("confidence_skill");
        double rich = conf != null ? conf / 100.0 : a.knowledgeScore() / 100.0;
        Soil soil = new Soil(r2(rich), Math.min(5, 1 + trainings), trainings, PartStatus.of(rich),
                conf != null
                        ? String.format("Financial confidence & skill %.0f/100 (CFPB scanner) · %d learning modules completed.", conf, trainings)
                        : String.format("Knowledge %d/100 · %d learning modules completed.", a.knowledgeScore(), trainings));

        // Weather from the user's situation
        Weather weather = a.context().has(SituationFlag.VARIABLE_INCOME) || a.context().has(SituationFlag.STARTING_BUSINESS)
                ? new Weather(Weather.Type.WINDY, "Your income varies from month to month.")
                : a.bufferMonths() < 1 ? new Weather(Weather.Type.BREEZY, "Little buffer: small surprises shake the tree.")
                : new Weather(Weather.Type.CALM, "No unusual pressure right now.");

        // Blossoms = milestones
        List<String> blossoms = new ArrayList<>();
        if (a.bufferMonths() >= 3) blossoms.add("3-month safety buffer reached");
        if (d.profile().monthsInvestedLast12() >= 12) blossoms.add("Invested every month this year");
        d.projects().stream().filter(p -> p.progress() >= 1).forEach(p -> blossoms.add("“" + p.name() + "” fully funded"));

        double wealth = d.pots().stream().mapToDouble(SavingsPot::balance).sum()
                + d.holdings().stream().mapToDouble(Holding::value).sum();
        TreeState.Stage stage = wealth < 20_000 ? TreeState.Stage.SAPLING : wealth < 150_000 ? TreeState.Stage.YOUNG : TreeState.Stage.MATURE;

        // Tree health = half "what you tell us" (CFPB peer percentile), half "what your accounts show" (bank-data score),
        // so it reacts to habits month by month, not only when questionnaire answers change.
        int overall = wb != null && wb.percentile() != null ? (int) Math.round(0.5 * wb.percentile() + 0.5 * a.overallScore()) : a.overallScore();
        return new TreeState(d.profile().id(), d.profile().name(), stage, overall,
                PartStatus.of(overall / 100.0), headline(a), roots, trunk, leaves, branches, soil, weather, blossoms, wb, null);
    }

    /** Storm test: a market drop of the size a bad year could bring for the user's risk profile. */
    public StormResult storm(UserData d, Assessment a) {
        double invested = d.holdings().stream().filter(h -> h.assetClass() != AssetClass.CASH).mapToDouble(Holding::value).sum();
        double drop = invested * d.profile().riskTolerance().badYearDrop;
        boolean recovers = a.bufferMonths() >= 3 && a.diversification() >= 0.6;
        double lean = recovers ? 6 : a.bufferMonths() >= 3 || a.diversification() >= 0.6 ? 10 : 14;
        if (invested <= 0) {
            return new StormResult(a.bufferMonths() >= 3, a.bufferMonths() >= 3 ? 4 : 9, 0, a.bufferMonths() >= 3
                    ? "Nothing invested yet, and your buffer covers life’s storms. Ready to grow a trunk."
                    : String.format("Nothing invested yet, so markets can’t hurt you. But with %.1f months of buffer, a personal storm (a repair, a job gap) could.", a.bufferMonths()));
        }
        String msg = recovers
                ? String.format("Deep roots: a €%,.0f drop bends the tree, but your buffer means you never have to sell.", drop)
                : a.bufferMonths() < 3
                ? String.format("Shallow roots: a €%,.0f drop could force you to sell when prices are low.", drop)
                : String.format("A concentrated trunk: a €%,.0f drop hits one position hard.", drop);
        return new StormResult(recovers, lean, Math.round(drop), msg);
    }

    private static String headline(Assessment a) {
        if (a.overallScore() >= 75) return "Deep roots, steady growth";
        if (a.spendScore() < 50 && a.spendScore() <= a.savingsScore()) return "Full of life, but the leaves need care";
        if (a.savingsScore() < 50) return "Growing, but the roots are shallow";
        if (a.spendScore() < 50) return "Full of life, but the leaves need care";
        if (a.investScore() < 50) return "Solid roots, but the trunk is still young";
        return "Growing steadily";
    }

    static double clamp(double v) { return Math.max(0, Math.min(1, v)); }
    static double r2(double v) { return Math.round(v * 100) / 100.0; }
}
