package com.futurebuild.wealthtree.profiles;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.futurebuild.wealthtree.data.DemoData;
import com.futurebuild.wealthtree.data.UserRepository;
import com.futurebuild.wealthtree.kairos.KairosPersonas;
import com.futurebuild.wealthtree.model.AssetClass;
import com.futurebuild.wealthtree.model.Holding;
import com.futurebuild.wealthtree.model.Project;
import com.futurebuild.wealthtree.model.RiskTolerance;
import com.futurebuild.wealthtree.model.SavingsCategory;
import com.futurebuild.wealthtree.model.SavingsPot;
import com.futurebuild.wealthtree.model.SpendingCategory;
import com.futurebuild.wealthtree.model.Transaction;
import com.futurebuild.wealthtree.model.UserData;
import com.futurebuild.wealthtree.model.UserProfile;
import com.futurebuild.wealthtree.prediction.PredictionService;
import com.futurebuild.wealthtree.progress.ProgressService;
import com.futurebuild.wealthtree.scanner.ScannerAnswers;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.NoSuchElementException;

/**
 * Creates, personalises and deletes customer-made profiles. One form (ProfileRequest) becomes the same
 * three inputs the demo personas have: bank data (UserData), the agents' extra facts (KairosPersonas.Extras)
 * and questionnaire answers for the scanner. Profiles are saved to a JSON file and reloaded at start.
 */
public class ProfileService {

    private final UserRepository repo;
    private final PredictionService predictions;
    private final ProgressService progress;
    private final ObjectMapper json;
    private final Path file;
    private final SecureRandom random = new SecureRandom();

    /** Construct after ProgressService: it restores each customer's evolved data, which loading keeps. */
    public ProfileService(UserRepository repo, PredictionService predictions, ProgressService progress, ObjectMapper json, Path file) {
        this.repo = repo;
        this.predictions = predictions;
        this.progress = progress;
        this.json = json;
        this.file = file;
        load();
    }

    public record Summary(String id, String name, int age, boolean custom) {}

    public List<Summary> list() {
        List<Summary> out = new ArrayList<>();
        for (UserData d : repo.findAll()) {
            out.add(new Summary(d.profile().id(), d.profile().name(), d.profile().age(), CustomProfiles.has(d.profile().id())));
        }
        out.sort((a, b) -> a.custom() != b.custom() ? (a.custom() ? 1 : -1) : a.name().compareToIgnoreCase(b.name()));
        return out;
    }

    public synchronized Summary create(ProfileRequest raw) {
        ProfileRequest r = raw.validated();
        if (CustomProfiles.data().size() >= 50) throw new IllegalArgumentException("Too many profiles on this demo machine.");
        String id = newId(r.name());
        register(id, r, true);
        save();
        predictions.refresh(id);                       // agents start working right away
        return new Summary(id, r.name(), r.age(), true);
    }

    public synchronized Summary update(String id, ProfileRequest raw) {
        if (!CustomProfiles.has(id)) {
            repo.findById(id).orElseThrow(() -> new NoSuchElementException("No such customer: " + id));
            throw new IllegalArgumentException("Demo customers are read-only. Create your own copy to personalise it.");
        }
        ProfileRequest r = raw.validated();
        register(id, r, true);
        progress.forget(id);                           // new facts: the tree's memory starts over
        save();
        predictions.refresh(id);
        return new Summary(id, r.name(), r.age(), true);
    }

    public synchronized void delete(String id) {
        if (!CustomProfiles.has(id)) throw new IllegalArgumentException("Only profiles you created can be deleted.");
        CustomProfiles.remove(id);
        repo.delete(id);
        progress.forget(id);
        save();
    }

    /** The form for any customer: a created profile as saved, a demo persona converted (to copy it). */
    public ProfileRequest form(String id) {
        return CustomProfiles.get(id).map(CustomProfiles.Entry::request).orElseGet(() -> fromExisting(id));
    }

    // ------------------------------------------------------------------ building
    /** fresh=false (start-up): keep the data progress memory restored (months advanced, balances moved). */
    private void register(String id, ProfileRequest r, boolean fresh) {
        UserData data = userData(id, r);
        CustomProfiles.put(id, new CustomProfiles.Entry(r, data, extras(r), answers(r)));
        if (fresh || repo.findById(id).isEmpty()) repo.save(data);
    }

    static UserData userData(String id, ProfileRequest r) {
        List<String> goalLabels = r.goals().stream().map(g -> switch (g.type()) {
            case "home" -> "Save for a home in " + g.years() + " years";
            case "keep" -> "Do not lose what I have";
            default -> "Build " + Math.round(g.target()) + " EUR of wealth";
        }).toList();
        String situation = r.situation().isBlank() ? "My money is mainly for: " + r.purpose() + "." : r.situation();
        UserProfile p = new UserProfile(id, r.name(), r.age(), r.monthlyIncome(), RiskTolerance.valueOf(r.riskTolerance()),
                situation, goalLabels, (r.knowledge() - 1) / 6.0, List.of(),
                r.investments() > 0 || r.monthlySavingInvested() > 0 ? (r.monthlySavingInvested() > 0 ? 12 : 3) : 0, 0);
        List<SavingsPot> pots = new ArrayList<>();
        pots.add(new SavingsPot(id + "-emergency", SavingsCategory.EMERGENCY, "Savings account", r.cashSavings(), 0));
        if (r.disabilityCover()) pots.add(new SavingsPot(id + "-protection", SavingsCategory.PROTECTION, "Income protection", 0, 0));
        List<Holding> holdings = new ArrayList<>();
        if (r.investments() > 0) holdings.add(new Holding("Funds and ETFs", AssetClass.EQUITY_FUND, r.investments()));
        if (r.companyShares() > 0) {
            String label = switch (r.lifeStage()) {
                case "heir" -> "Family company shares";
                case "founder" -> "Own company stake";
                default -> "Single company shares";
            };
            holdings.add(new Holding(label, AssetClass.SINGLE_STOCK, r.companyShares()));
        }
        Map<SpendingCategory, double[]> plan = new EnumMap<>(SpendingCategory.class);
        r.spending().forEach((k, v) -> plan.put(SpendingCategory.valueOf(k), new double[]{v, v}));
        List<Transaction> tx = DemoData.spending(plan);
        return new UserData(p, List.copyOf(pots), List.copyOf(holdings), tx, List.<Project>of());
    }

    static KairosPersonas.Extras extras(ProfileRequest r) {
        List<Map<String, Object>> goals = new ArrayList<>();
        for (ProfileRequest.Goal g : r.goals()) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("type", g.type());
            if (g.target() != null) m.put("target", Math.round(g.target()));
            if (g.years() != null) m.put("years", g.years());
            m.put("priority", g.priority());
            goals.add(m);
        }
        return new KairosPersonas.Extras(r.lifeStage(), r.purpose(), r.crashReaction(), r.will(),
                r.monthlySavingCash(), r.monthlySavingInvested(), null, null, r.horizonYears(), List.copyOf(goals),
                r.subscriptions().stream().map(s -> new KairosPersonas.Subscription(s.name(), s.monthly(), s.lastUsedDays())).toList(),
                r.plannedPurchases().stream().map(p -> new KairosPersonas.Purchase(p.label(), p.amount(), p.inMonths())).toList(),
                r.incomeNote());
    }

    /** Questionnaire answers (CFPB codes) for the scanner: a neutral base, set by what the customer told us. */
    static Map<String, Object> answers(ProfileRequest r) {
        Map<String, Object> a = new LinkedHashMap<>(ScannerAnswers.get("lena").orElseGet(LinkedHashMap::new));
        a.put("age", r.age());
        double usd = r.cashSavings();
        a.put("SAVINGSRANGES", usd <= 0 ? 1 : usd < 100 ? 2 : usd < 1_000 ? 3 : usd < 5_000 ? 4 : usd < 20_000 ? 5 : usd < 75_000 ? 6 : 7);
        a.put("ABSORBSHOCK", r.shockAbsorb());
        for (String k : List.of("FS1_1", "FS1_2", "FS1_3", "FS1_4", "FS1_5", "FS1_6", "FS1_7")) a.put(k, r.confidence());
        a.put("GOALCONF", Math.max(1, Math.min(4, (int) Math.round(r.confidence() * 0.8))));
        a.put("SUBKNOWL1", r.knowledge());
        a.put("PRODHAVE_2", r.disabilityCover() ? 1 : 0);
        a.put("PRODHAVE_6", r.investments() > 0 ? 1 : 0);
        a.put("AUTOMATED_2", r.monthlySavingCash() > 0 ? 1 : 0);
        return a;
    }

    private ProfileRequest fromExisting(String id) {
        UserData d = repo.findById(id).orElseThrow(() -> new NoSuchElementException("No such customer: " + id));
        KairosPersonas.Extras x = KairosPersonas.get(id).orElse(null);
        Map<String, Object> ans = ScannerAnswers.get(id).orElseGet(LinkedHashMap::new);
        Map<SpendingCategory, Double> total = new EnumMap<>(SpendingCategory.class);
        java.util.Set<java.time.YearMonth> months = new java.util.HashSet<>();
        for (Transaction t : d.transactions()) {
            total.merge(t.category(), t.amount(), Double::sum);
            months.add(java.time.YearMonth.from(t.date()));
        }
        Map<String, Double> spending = new LinkedHashMap<>();
        int n = Math.max(1, months.size());
        total.forEach((k, v) -> spending.put(k.name(), (double) Math.round(v / n)));
        double cash = d.pots().stream().filter(p -> p.category() == SavingsCategory.EMERGENCY || p.category() == SavingsCategory.GOALS)
                .mapToDouble(SavingsPot::balance).sum()
                + d.holdings().stream().filter(h -> h.assetClass() == AssetClass.CASH).mapToDouble(Holding::value).sum();
        double company = d.holdings().stream().filter(h -> h.assetClass() == AssetClass.SINGLE_STOCK).mapToDouble(Holding::value).sum();
        double invested = d.holdings().stream().filter(h -> h.assetClass() != AssetClass.CASH && h.assetClass() != AssetClass.SINGLE_STOCK)
                .mapToDouble(Holding::value).sum()
                + d.pots().stream().filter(p -> p.category() == SavingsCategory.RETIREMENT).mapToDouble(SavingsPot::balance).sum()
                + d.projects().stream().mapToDouble(Project::savedAmount).sum();
        List<ProfileRequest.Goal> goals = new ArrayList<>();
        if (x != null) {
            for (Map<String, Object> g : x.goals()) {
                goals.add(new ProfileRequest.Goal((String) g.get("type"),
                        g.get("target") instanceof Number t ? t.doubleValue() : null,
                        g.get("years") instanceof Number y ? y.intValue() : null,
                        g.get("priority") instanceof Number p ? p.intValue() : goals.size() + 1));
            }
        }
        if (goals.isEmpty()) goals.add(new ProfileRequest.Goal("keep", null, null, 1));
        return new ProfileRequest(d.profile().name(), d.profile().age(), x == null ? "pro" : x.profile(),
                x == null ? "Security" : x.purpose(), d.profile().situation(), d.profile().riskTolerance().name(),
                d.profile().netMonthlyIncome(), x == null ? null : x.incomeNote(), spending, (double) Math.round(cash),
                (double) Math.round(invested), (double) Math.round(company),
                x == null ? 0.0 : x.baseSavingCash(), x == null ? 0.0 : x.baseSavingInvested(),
                x == null ? "hold" : x.crashReaction(),
                d.pots().stream().anyMatch(p -> p.category() == SavingsCategory.PROTECTION), x != null && x.will(),
                num(ans, "FS1_1", 3), num(ans, "SUBKNOWL1", 4), num(ans, "ABSORBSHOCK", 2),
                x == null ? 15 : x.horizonYears(), goals,
                x == null ? List.of() : x.subscriptions().stream()
                        .map(s -> new ProfileRequest.Subscription(s.name(), s.monthly(), s.lastUsedDays())).toList(),
                x == null ? List.of() : x.plannedPurchases().stream()
                        .map(p -> new ProfileRequest.Purchase(p.label(), p.amount(), p.inMonths())).toList());
    }

    private static int num(Map<String, Object> a, String k, int fallback) {
        return a.get(k) instanceof Number n ? n.intValue() : fallback;
    }

    private String newId(String name) {
        String slug = name.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]+", "-").replaceAll("(^-|-$)", "");
        if (slug.isEmpty()) slug = "customer";
        if (slug.length() > 20) slug = slug.substring(0, 20);
        String id;
        do {
            id = "p-" + slug + "-" + Integer.toHexString(0x1000 + random.nextInt(0xF000));
        } while (repo.findById(id).isPresent());
        return id;
    }

    // ------------------------------------------------------------------ persistence
    private void load() {
        if (file == null || !Files.exists(file)) return;
        try {
            Map<String, ProfileRequest> saved = json.readValue(file.toFile(), new TypeReference<Map<String, ProfileRequest>>() {});
            saved.forEach((id, r) -> {
                try {
                    register(id, r.validated(), false);
                } catch (IllegalArgumentException e) {
                    System.err.println("Skipping saved profile " + id + ": " + e.getMessage());
                }
            });
        } catch (IOException e) {
            System.err.println("Could not read " + file + ": " + e.getMessage());
        }
    }

    private void save() {
        if (file == null) return;
        try {
            if (file.getParent() != null) Files.createDirectories(file.getParent());
            Path tmp = file.resolveSibling(file.getFileName() + ".tmp");
            json.writerWithDefaultPrettyPrinter().writeValue(tmp.toFile(), CustomProfiles.requests());
            Files.move(tmp, file, java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            System.err.println("Could not save " + file + ": " + e.getMessage());
        }
    }
}
