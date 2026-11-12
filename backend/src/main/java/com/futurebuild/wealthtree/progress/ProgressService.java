package com.futurebuild.wealthtree.progress;

import com.futurebuild.wealthtree.app.WealthTreeService;
import com.futurebuild.wealthtree.assessment.Assessment;
import com.futurebuild.wealthtree.assessment.HabitHealth;
import com.futurebuild.wealthtree.assessment.SpendingHabit;
import com.futurebuild.wealthtree.data.UserRepository;
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
import com.futurebuild.wealthtree.recommendation.ActionType;
import com.futurebuild.wealthtree.recommendation.Recommendation;
import com.futurebuild.wealthtree.scanner.ScannerAnswers;
import com.futurebuild.wealthtree.tree.TreeState;

import java.time.YearMonth;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Objects;
import java.util.Random;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * Remembers each user over time and lets the tree grow or shrink.
 *
 * Only INPUTS are changed (transactions, pots, holdings, questionnaire answers, committed actions);
 * every score is recalculated from them, so nothing has to be updated by hand. Each month:
 *  1. new spending is generated from the user's own pattern (bad trends keep growing unless a limit is committed),
 *  2. committed actions run (standing orders, investment steps…) and are VERIFIED only when the data shows them,
 *  3. investments move with a seeded market (they can fall: the trunk can shrink),
 *  4. facts in the questionnaire are re-derived from the data (e.g. the savings band),
 *  5. the tree is recalculated, compared with last month, and a snapshot is stored with what changed.
 * Everything is saved to a file, so the tree remembers across restarts.
 */
public class ProgressService {

    private final WealthTreeService service;
    private final UserRepository repo;
    private final StateStore store;
    private final Map<String, UserProgress> progress = new ConcurrentHashMap<>();

    public record MonthResult(YearMonth month, int treeHealth, List<String> events) {}
    public record AdvanceResult(List<MonthResult> months, TreeState tree, ProgressSummary progress) {}
    public record History(String userId, List<Snapshot> snapshots, List<TrackedAction> actions, List<String> milestones) {}

    public ProgressService(WealthTreeService service, UserRepository repo, StateStore store) {
        this.service = service;
        this.repo = repo;
        this.store = store;
        StateStore.State saved = store.load();
        if (saved != null) {
            saved.users().values().forEach(repo::save);
            progress.putAll(saved.progress());
        }
        service.setAnswersProvider(this::answers);
        service.setProgressProvider(this::summary);
    }

    // ------------------------------------------------------------------ queries
    public synchronized Map<String, Object> answers(String id) {
        return new LinkedHashMap<>(ensure(id).answers);
    }

    public synchronized ProgressSummary summary(String id) {
        UserProgress p = ensure(id);
        List<Snapshot> h = p.history;
        Integer last = h.size() >= 2 ? h.get(h.size() - 1).treeHealth() - h.get(h.size() - 2).treeHealth() : null;
        Integer start = h.size() >= 2 ? h.get(h.size() - 1).treeHealth() - h.get(0).treeHealth() : null;
        ProgressSummary.Trend trend = last == null ? ProgressSummary.Trend.NEW
                : last > 0 ? ProgressSummary.Trend.GROWING : last < 0 ? ProgressSummary.Trend.SHRINKING : ProgressSummary.Trend.STABLE;
        List<String> latest = h.isEmpty() ? List.of() : h.get(h.size() - 1).events();
        return new ProgressSummary(p.month, Math.max(0, h.size() - 1), last, start, trend, latest,
                List.copyOf(p.milestones), List.copyOf(p.actions));
    }

    public synchronized History history(String id) {
        UserProgress p = ensure(id);
        return new History(id, List.copyOf(p.history), List.copyOf(p.actions), List.copyOf(p.milestones));
    }

    // ------------------------------------------------------------------ commands
    public synchronized ProgressSummary commit(String id, String actionOrRecId) {
        UserProgress p = ensure(id);
        Recommendation r = service.recommendations(id).stream()
                .filter(x -> x.action().id().equals(actionOrRecId) || x.id().equals(actionOrRecId)).findFirst()
                .orElseThrow(() -> new NoSuchElementException("No such recommended action: " + actionOrRecId));
        Action a = r.action();
        TrackedAction existing = p.actions.stream().filter(t -> t.actionId().equals(a.id()) && t.active()).findFirst().orElse(null);
        boolean sameStep = existing != null && existing.monthlyAmount() == a.monthlyAmount() && existing.oneOffAmount() == a.oneOffAmount();
        if (!sameStep) {
            // a new version of the same action (e.g. eating-out limit €450 -> €300) replaces the old one
            if (existing != null) p.actions.set(p.actions.indexOf(existing), existing.withStatus(ActionStatus.REPLACED));
            p.actions.add(new TrackedAction(a.id(), r.id(), a.title(), a.type(), a.target(), a.monthlyAmount(), a.oneOffAmount(),
                    r.training() == null ? null : r.training().id(), ActionStatus.COMMITTED, p.month, null, null, 0));
            persist();
        }
        return summary(id);
    }

    public synchronized ProgressSummary drop(String id, String actionId) {
        UserProgress p = ensure(id);
        p.actions.replaceAll(a -> a.actionId().equals(actionId) && a.active() ? a.withStatus(ActionStatus.DROPPED) : a);
        persist();
        return summary(id);
    }

    public synchronized AdvanceResult advance(String id, int months) {
        ensure(id);
        List<MonthResult> out = new ArrayList<>();
        for (int i = 0; i < Math.max(1, Math.min(months, 24)); i++) out.add(advanceOne(id));
        persist();
        return new AdvanceResult(out, service.tree(id), summary(id));
    }

    public synchronized void reset() {
        progress.clear();
        repo.reset();
        store.clear();
    }

    // ------------------------------------------------------------------ one month
    private MonthResult advanceOne(String id) {
        UserProgress p = progress.get(id);
        UserData d = service.user(id);
        YearMonth next = p.month.plusMonths(1);
        Random rnd = new Random(Objects.hash(id, next.toString()));
        List<String> events = new ArrayList<>();

        // 1. Spending: continue the user's own pattern; committed limits cap a category.
        Map<SpendingCategory, Double> limits = new EnumMap<>(SpendingCategory.class);
        for (TrackedAction a : p.actions)
            if (a.active() && a.type() == ActionType.SPENDING_LIMIT) limits.put(SpendingCategory.valueOf(a.target()), a.monthlyAmount());
        Map<SpendingCategory, Double> spend = nextMonthSpending(d.transactions(), limits, rnd);
        List<Transaction> tx = new ArrayList<>();
        YearMonth keepFrom = next.minusMonths(5);
        for (Transaction t : d.transactions()) if (!YearMonth.from(t.date()).isBefore(keepFrom)) tx.add(t);
        spend.forEach((c, amt) -> {
            tx.add(new Transaction(next.atDay(5), c, Math.round(amt * 0.6), c.label));
            tx.add(new Transaction(next.atDay(20), c, Math.round(amt * 0.4), c.label));
        });
        double spent = spend.values().stream().mapToDouble(Double::doubleValue).sum();

        // 2. Committed actions run; they are verified only when the data shows them.
        List<SavingsPot> pots = new ArrayList<>(d.pots());
        List<Holding> holdings = new ArrayList<>(d.holdings());
        List<Project> projects = new ArrayList<>(d.projects());
        UserProfile prof = d.profile();
        double knowledge = prof.knowledgeScore();
        List<String> trainings = new ArrayList<>(prof.completedTrainings());
        double fromIncome = 0;
        boolean investedThisMonth = false;

        for (int i = 0; i < p.actions.size(); i++) {
            TrackedAction a = p.actions.get(i);
            if (!a.active()) continue;
            boolean isNew = a.status() == ActionStatus.COMMITTED;
            TrackedAction updated = a;
            switch (a.type()) {
                case AUTO_SAVE -> {
                    addTo(pots, projects, a.target(), a.monthlyAmount());
                    fromIncome += a.monthlyAmount();
                    if (a.target().equals(SavingsCategory.RETIREMENT.name())) investedThisMonth = true;
                    if (isNew) updated = a.verified(next, String.format("standing order of €%,.0f arrived", a.monthlyAmount()));
                }
                case MOVE_CASH -> {
                    if (isNew) {
                        double moved = takeCash(holdings, a.oneOffAmount());
                        addTo(pots, projects, a.target(), moved);
                        updated = a.verified(next, String.format("€%,.0f moved", moved));
                    }
                }
                case INVEST_MONTHLY -> {
                    if (a.recommendationId().equals("rec-invest-idle")) {
                        if (a.stepsDone() < 12) {
                            double moved = takeCash(holdings, a.monthlyAmount());
                            addFund(holdings, moved);
                            updated = a.step();
                            if (isNew) updated = updated.verified(next, "first investment step executed");
                            if (moved > 0) investedThisMonth = true;
                        }
                    } else {
                        addFund(holdings, a.monthlyAmount());
                        fromIncome += a.monthlyAmount();
                        investedThisMonth = true;
                        if (isNew) updated = a.verified(next, String.format("savings plan of €%,.0f executed", a.monthlyAmount()));
                    }
                }
                case DIVERSIFY -> {
                    if (a.stepsDone() < 12) {
                        diversify(holdings, a.oneOffAmount() / 12);
                        updated = a.step();
                        if (isNew) updated = updated.verified(next, "first diversification step executed");
                    }
                }
                case PROTECT -> {
                    if (isNew) {
                        if (pots.stream().noneMatch(x -> x.category() == SavingsCategory.PROTECTION))
                            pots.add(new SavingsPot(id + "-protection", SavingsCategory.PROTECTION, "Disability cover", 0, 1));
                        updated = a.verified(next, "cover confirmed by your advisor");
                    }
                }
                case LEARN -> {
                    if (isNew) { knowledge = Math.min(1, knowledge + 0.1); updated = a.verified(next, "module completed"); }
                }
                case ADVISOR_MEETING, SEPARATE_ACCOUNTS -> {
                    if (isNew) updated = a.verified(next, "confirmed by your Relationship Manager");
                }
                case SPENDING_LIMIT -> {
                    SpendingCategory c = SpendingCategory.valueOf(a.target());
                    double s = spend.getOrDefault(c, 0.0);
                    if (isNew && s <= a.monthlyAmount())
                        updated = a.verified(next, String.format("%s stayed at €%,.0f, under the €%,.0f limit", c.label, s, a.monthlyAmount()));
                    else if (!isNew && s > a.monthlyAmount())
                        events.add(String.format("%s went over the limit this month: €%,.0f of €%,.0f.", c.label, s, a.monthlyAmount()));
                }
            }
            if (updated.status() == ActionStatus.VERIFIED && isNew) {
                events.add("Verified: " + a.title() + " (" + updated.evidence() + ").");
                if (a.trainingId() != null && !trainings.contains(a.trainingId())) trainings.add(a.trainingId());
                p.answers.putAll(ScannerAnswers.changeFor(asRecommendation(a), p.answers));
            }
            p.actions.set(i, updated);
        }

        // 3. Money left over lands on the current account; a shortfall comes out of cash, then the safety pot.
        double leftover = prof.netMonthlyIncome() - spent - fromIncome;
        if (leftover >= 0) addCash(holdings, leftover);
        else {
            double missing = -leftover - takeCash(holdings, -leftover);
            if (missing > 0) { addTo(pots, projects, SavingsCategory.EMERGENCY.name(), -missing); events.add(String.format("Spending exceeded income: €%,.0f taken from the safety pot.", missing)); }
        }

        // 4. Markets move (seeded, so the same month always gives the same result). Trunks can shrink.
        double before = holdings.stream().filter(h -> h.assetClass() != AssetClass.CASH).mapToDouble(Holding::value).sum();
        double zMarket = rnd.nextGaussian(), zStock = 0.3 * zMarket + Math.sqrt(1 - 0.09) * rnd.nextGaussian();
        holdings.replaceAll(h -> switch (h.assetClass()) {
            case CASH -> h;
            case SINGLE_STOCK -> h.withValue(h.value() * (1 + 0.07 / 12 + 0.30 / Math.sqrt(12) * zStock));
            case EQUITY_FUND -> h.withValue(h.value() * (1 + 0.06 / 12 + 0.15 / Math.sqrt(12) * zMarket));
            case BOND_FUND -> h.withValue(h.value() * (1 + 0.03 / 12 + 0.05 / Math.sqrt(12) * zMarket));
            case REAL_ESTATE -> h.withValue(h.value() * (1 + 0.03 / 12 + 0.06 / Math.sqrt(12) * zMarket));
        });
        double after = holdings.stream().filter(h -> h.assetClass() != AssetClass.CASH).mapToDouble(Holding::value).sum();
        if (before > 0 && Math.abs(after / before - 1) >= 0.03)
            events.add(String.format("Markets %s %.1f%%: your investments %s €%,.0f.", after < before ? "fell" : "rose",
                    Math.abs(after / before - 1) * 100, after < before ? "lost" : "gained", Math.abs(after - before)));

        // 5. Consistency: rolling 12 months; a full steady year adds a ring.
        p.investedMonths.add(investedThisMonth);
        while (p.investedMonths.size() > 12) p.investedMonths.remove(0);
        int monthsInvested = (int) p.investedMonths.stream().filter(b -> b).count();
        int years = prof.yearsConsistent();
        if (p.history.size() % 12 == 0 && p.investedMonths.size() == 12 && monthsInvested >= 10) {
            years++;
            events.add("A new ring: a full year of steady investing.");
        }

        UserProfile np = prof.withProgress(knowledge, List.copyOf(trainings), monthsInvested, years);
        UserData nd = new UserData(np, List.copyOf(pots), List.copyOf(holdings), List.copyOf(tx), List.copyOf(projects));
        repo.save(nd);
        deriveFacts(p.answers, nd);
        p.month = next;

        Snapshot s = snapshot(id, events);
        compare(p, s, events);
        p.history.add(new Snapshot(s.month(), s.treeHealth(), s.cfpbScore(), s.savingsScore(), s.investScore(), s.spendScore(),
                s.knowledgeScore(), s.bufferMonths(), s.savingsRate(), s.wantsShare(), s.liquidSavings(), s.invested(), s.netWorth(),
                s.leafHealth(), s.leafSpend(), s.rings(), s.headline(), List.copyOf(events)));
        return new MonthResult(next, s.treeHealth(), List.copyOf(events));
    }

    // ------------------------------------------------------------------ helpers
    private UserProgress ensure(String id) {
        UserProgress p = progress.get(id);
        if (p != null) return p;
        UserData d = service.user(id);
        Map<String, Object> answers = ScannerAnswers.get(id).orElseGet(LinkedHashMap::new);
        p = new UserProgress(id, YearMonth.now(), answers);
        deriveFacts(p.answers, d);
        progress.put(id, p);                                   // before the snapshot: the tree asks for answers
        p.history.add(snapshot(id, List.of("Started tracking.")));
        persist();
        return p;
    }

    private Snapshot snapshot(String id, List<String> events) {
        UserData d = service.user(id);
        Assessment a = service.assessment(id);
        TreeState t = service.tree(id);
        Map<String, String> leafHealth = new LinkedHashMap<>();
        Map<String, Double> leafSpend = new LinkedHashMap<>();
        for (SpendingHabit h : a.habits()) {
            leafHealth.put(h.category().name(), h.health().name());
            leafSpend.put(h.category().name(), h.monthlyAverage());
        }
        double liquid = liquid(d);
        double invested = d.holdings().stream().filter(h -> h.assetClass() != AssetClass.CASH).mapToDouble(Holding::value).sum();
        double net = d.pots().stream().mapToDouble(SavingsPot::balance).sum() + d.holdings().stream().mapToDouble(Holding::value).sum()
                + d.projects().stream().mapToDouble(Project::savedAmount).sum();
        return new Snapshot(progress.get(id).month, t.overallHealth(), t.wellbeing() == null ? null : t.wellbeing().predictedScore(),
                a.savingsScore(), a.investScore(), a.spendScore(), a.knowledgeScore(), a.bufferMonths(), a.savingsRate(), a.wantsShare(),
                Math.round(liquid), Math.round(invested), Math.round(net), leafHealth, leafSpend, t.trunk().rings(), t.headline(), List.copyOf(events));
    }

    /** Plain-language changes vs last month, plus milestones (blossoms) that are remembered forever. */
    private void compare(UserProgress p, Snapshot now, List<String> events) {
        Snapshot prev = p.history.get(p.history.size() - 1);
        int dh = now.treeHealth() - prev.treeHealth();
        if (dh != 0) events.add(0, String.format("Tree health %d → %d (%s%d): the tree is %s.", prev.treeHealth(), now.treeHealth(),
                dh > 0 ? "+" : "", dh, dh > 0 ? "growing" : "shrinking"));
        else events.add(0, String.format("Tree health stable at %d.", now.treeHealth()));
        for (Map.Entry<String, String> e : now.leafHealth().entrySet()) {
            String was = prev.leafHealth().get(e.getKey());
            if (was == null || was.equals(e.getValue())) continue;
            String label = SpendingCategory.valueOf(e.getKey()).label;
            boolean better = rank(e.getValue()) > rank(was);
            events.add(String.format("%s leaves %s: %s → %s (€%,.0f a month on average).", label, better ? "recovered" : "got worse",
                    was.toLowerCase(), e.getValue().toLowerCase(), now.leafSpend().get(e.getKey())));
        }
        if (Math.abs(now.bufferMonths() - prev.bufferMonths()) >= 0.25)
            events.add(String.format("Safety roots %s: %.1f → %.1f months of costs.", now.bufferMonths() > prev.bufferMonths() ? "grew" : "shrank",
                    prev.bufferMonths(), now.bufferMonths()));

        bloom(p, events, now.bufferMonths() >= 3, "3-month safety buffer reached in " + now.month());
        bloom(p, events, now.bufferMonths() >= 6, "6-month safety buffer reached in " + now.month());
        bloom(p, events, !now.leafHealth().isEmpty() && now.leafHealth().values().stream().allMatch(v -> v.equals("HEALTHY")),
                "All leaves healthy in " + now.month());
        bloom(p, events, now.treeHealth() >= 70, "Tree health 70+ in " + now.month());
        bloom(p, events, now.treeHealth() - p.history.get(0).treeHealth() >= 10, "+10 tree health since you started (" + now.month() + ")");
        for (Map.Entry<String, String> e : now.leafHealth().entrySet()) {
            String first = p.history.get(0).leafHealth().get(e.getKey());
            bloom(p, events, "ROTTEN".equals(first) && e.getValue().equals("HEALTHY"),
                    SpendingCategory.valueOf(e.getKey()).label + " healed (" + now.month() + ")");
        }
    }

    private static void bloom(UserProgress p, List<String> events, boolean reached, String text) {
        String key = text.replaceAll(" (in|\\()\\s?\\d{4}-\\d{2}\\)?$", "");
        if (reached && p.milestones.stream().noneMatch(m -> m.startsWith(key))) {
            p.milestones.add(text);
            events.add("Blossom: " + text + ".");
        }
    }

    private static int rank(String h) { return h.equals("HEALTHY") ? 2 : h.equals("WILTING") ? 1 : 0; }

    /** Next month per category: recent 3-month level moved by (half of) the recent trend, small noise, capped by limits.
     *  Essentials (rent, groceries) stay stable; wants keep following their trend unless a limit is committed. */
    static Map<SpendingCategory, Double> nextMonthSpending(List<Transaction> tx, Map<SpendingCategory, Double> limits, Random rnd) {
        Map<YearMonth, Map<SpendingCategory, Double>> byMonth = new TreeMap<>();
        for (Transaction t : tx)
            byMonth.computeIfAbsent(YearMonth.from(t.date()), k -> new EnumMap<>(SpendingCategory.class)).merge(t.category(), t.amount(), Double::sum);
        List<YearMonth> keys = new ArrayList<>(byMonth.keySet());
        Map<SpendingCategory, Double> out = new EnumMap<>(SpendingCategory.class);
        if (keys.isEmpty()) return out;
        Map<SpendingCategory, Double> last = byMonth.get(keys.get(keys.size() - 1));
        for (SpendingCategory c : SpendingCategory.values()) {
            if (last.get(c) == null) continue;
            // level = last month, but noise never compounds: start from the 3-month average moved by the trend
            int n = Math.min(3, keys.size());
            double level = 0;
            for (int i = keys.size() - n; i < keys.size(); i++) level += byMonth.get(keys.get(i)).getOrDefault(c, 0.0);
            level /= n;
            double g = 0;
            if (!c.essential && keys.size() >= 6) {           // rent and groceries stay stable; wants follow their trend
                double f = 0, r = 0;
                for (int i = 0; i < 3; i++) {
                    f += byMonth.get(keys.get(keys.size() - 6 + i)).getOrDefault(c, 0.0);
                    r += byMonth.get(keys.get(keys.size() - 3 + i)).getOrDefault(c, 0.0);
                }
                if (f > 0) g = Math.max(-0.05, Math.min(0.05, Math.pow(r / f, 1 / 3.0) - 1)) * 0.5;
            }
            double amt = level * Math.pow(1 + g, 2) * (1 + rnd.nextGaussian() * (c.essential ? 0.01 : 0.03));
            Double limit = limits.get(c);
            if (limit != null) amt = Math.min(amt, limit * (0.92 + rnd.nextDouble() * 0.12));   // mostly keeps the limit
            out.put(c, (double) Math.round(amt));
        }
        return out;
    }

    /** Facts the bank can see are re-derived every month (self-assessed answers only change with actions or a new check-up). */
    static void deriveFacts(Map<String, Object> a, UserData d) {
        double liquid = liquid(d);
        int band = liquid <= 0 ? 1 : liquid < 100 ? 2 : liquid < 1_000 ? 3 : liquid < 5_000 ? 4 : liquid < 20_000 ? 5 : liquid < 75_000 ? 6 : 7;
        a.put("SAVINGSRANGES", band);
        boolean invests = d.holdings().stream().anyMatch(h -> h.assetClass() != AssetClass.CASH && h.assetClass() != AssetClass.REAL_ESTATE && h.value() > 0);
        if (invests) a.put("PRODHAVE_6", 1);
        if (d.pots().stream().anyMatch(x -> x.category() == SavingsCategory.RETIREMENT)) a.put("PRODHAVE_4", 1);
        if (d.pots().stream().anyMatch(x -> x.category() == SavingsCategory.PROTECTION)) a.put("PRODHAVE_2", 1);
    }

    static double liquid(UserData d) {
        return d.pots().stream().filter(x -> x.category() == SavingsCategory.EMERGENCY || x.category() == SavingsCategory.GOALS).mapToDouble(SavingsPot::balance).sum()
                + d.holdings().stream().filter(h -> h.assetClass() == AssetClass.CASH).mapToDouble(Holding::value).sum()
                + d.projects().stream().mapToDouble(Project::savedAmount).sum();
    }

    private static Recommendation asRecommendation(TrackedAction a) {
        return new Recommendation(a.recommendationId(), null, 0, a.title(), "",
                new Action(a.actionId(), a.type(), a.title(), a.target(), a.monthlyAmount(), a.oneOffAmount(), null), null, 0, null);
    }

    private static void addTo(List<SavingsPot> pots, List<Project> projects, String target, double amount) {
        for (int i = 0; i < projects.size(); i++)
            if (projects.get(i).id().equals(target)) { projects.set(i, projects.get(i).withSaved(Math.max(0, projects.get(i).savedAmount() + amount))); return; }
        SavingsCategory c = SavingsCategory.valueOf(target);
        for (int i = 0; i < pots.size(); i++)
            if (pots.get(i).category() == c) { pots.set(i, pots.get(i).withBalance(Math.max(0, pots.get(i).balance() + amount))); return; }
        pots.add(new SavingsPot("pot-" + c.name().toLowerCase(), c, c.description, Math.max(0, amount), 0));
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

    private static void addCash(List<Holding> holdings, double amount) {
        for (int i = 0; i < holdings.size(); i++)
            if (holdings.get(i).assetClass() == AssetClass.CASH) { holdings.set(i, holdings.get(i).withValue(holdings.get(i).value() + amount)); return; }
        holdings.add(new Holding("Current account", AssetClass.CASH, amount));
    }

    private static void addFund(List<Holding> holdings, double amount) {
        if (amount <= 0) return;
        for (int i = 0; i < holdings.size(); i++)
            if (holdings.get(i).name().equals("Diversified portfolio")) { holdings.set(i, holdings.get(i).withValue(holdings.get(i).value() + amount)); return; }
        holdings.add(new Holding("Diversified portfolio", AssetClass.EQUITY_FUND, amount));
    }

    private static void diversify(List<Holding> holdings, double amount) {
        int idx = -1;
        for (int i = 0; i < holdings.size(); i++)
            if (holdings.get(i).assetClass() == AssetClass.SINGLE_STOCK && (idx < 0 || holdings.get(i).value() > holdings.get(idx).value())) idx = i;
        if (idx < 0) return;
        double m = Math.min(amount, holdings.get(idx).value());
        holdings.set(idx, holdings.get(idx).withValue(holdings.get(idx).value() - m));
        addFund(holdings, m);
    }

    private void persist() {
        store.save(new StateStore.State(
                repo.findAll().stream().collect(Collectors.toMap(x -> x.profile().id(), x -> x, (a, b) -> a, LinkedHashMap::new)),
                new LinkedHashMap<>(progress)));
    }
}
