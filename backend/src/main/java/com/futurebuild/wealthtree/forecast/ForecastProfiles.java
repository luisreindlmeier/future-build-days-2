package com.futurebuild.wealthtree.forecast;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Hardcoded demo customers for the engine. Max is the team demo's heir (numbers identical to
 * checkup-demo.html, so the output matches prediction-agent/example_input.json). Lena, Alex and Maya
 * are the challenge personas, consistent with DemoData.
 */
public final class ForecastProfiles {
    private ForecastProfiles() {}

    private static final Map<String, ForecastProfile> ALL = new LinkedHashMap<>();

    static {
        // ---- Max, 26, heir: 1:1 the team demo ------------------------------------------------
        World maxBase = new World(0.82, false, 180, 0, false, true, false);
        ALL.put("max", new ForecastProfile("max", "Max", 26, "heir", 15,
                new Finances(490_000, 3_100, 0, 3_000, 2_820), maxBase,
                habits("monthly_saving", "€180", "crash_reaction", "sold everything in the crash test",
                        "single_company_share", "82%", "disability_cover", "no", "will", "no",
                        "savings_rate", "6% of income"),
                List.of(new ForecastGoal("g1", "Build €1m of wealth by age 41", 1_000_000, 15, 1)),
                List.of(
                        new PlannedChange("buffer", "Save €400 a month into a buffer",
                                "Standing order of €400 a month into an emergency pot",
                                "Confirm the prepared standing order: €400 on the 1st of each month into a new emergency pot.",
                                w -> w.withSaveCash(w.saveCash() + 400)),
                        new PlannedChange("invest", "Invest €150 a month",
                                "Half of each future raise goes into a monthly investment plan, about €150 a month",
                                "Confirm the save-more-tomorrow commitment: half of your next raise goes into your monthly investment plan.",
                                w -> w.withSaveInv(w.saveInv() + 150)),
                        new PlannedChange("hold_rule", "Hold by written rule in a crash",
                                "Follow written rules in a market fall instead of selling",
                                "Write down your rules for a falling market with your advisor, then practise them in the crash review.",
                                World::holding),
                        new PlannedChange("diversify", "Diversify the family company shares",
                                "Reduce the single-company share from 82% to 60% over several years",
                                "Book the family-table session with your advisor and your parents to agree a step-by-step plan.",
                                World::withGlide),
                        new PlannedChange("cover", "Get disability cover", "Put income-protection cover in place",
                                "Book the 15-minute income protection check with a specialist.", World::withCover))));

        // ---- Lena, 24, first salary ------------------------------------------------------------
        ALL.put("lena", new ForecastProfile("lena", "Lena", 24, "pro", 11,
                new Finances(2_100, 2_100, 0, 2_900, 2_065), new World(0, false, 150, 0, false, false, false),
                habits("monthly_saving", "about €150, saved in 4 of the last 6 months", "emergency_buffer", "0.4 months of costs",
                        "eating_out", "€380 a month, up 29%", "crash_reaction", "held in the crash test",
                        "disability_cover", "no", "investing", "nothing invested yet"),
                List.of(new ForecastGoal("g1", "Build €100k of wealth by age 35", 100_000, 11, 1),
                        new ForecastGoal("g2", "Have €10k set aside by age 27", 10_000, 3, 2)),
                List.of(
                        new PlannedChange("buffer", "Save €250 on every payday",
                                "Standing order of €250 on payday into a safety pot",
                                "Confirm the prepared standing order: €250 on payday into a new safety pot.",
                                w -> w.withSaveCash(w.saveCash() + 250)),
                        new PlannedChange("eating_out_limit", "Cap eating out at €300 a month",
                                "Set a €300 monthly limit for eating out and save the difference",
                                "Switch on the €300 eating-out limit with alerts in the app.",
                                w -> w.withSaveCash(w.saveCash() + 80)),
                        new PlannedChange("invest", "Invest €150 a month",
                                "Start a €150 monthly savings plan in a broad fund",
                                "Set up the €150 monthly savings plan, starting next payday.",
                                w -> w.withSaveInv(w.saveInv() + 150)),
                        new PlannedChange("cover", "Get disability cover", "Put income-protection cover in place",
                                "Book the 15-minute income protection check with a specialist.", World::withCover))));

        // ---- Alex, 29, starting a business ---------------------------------------------------
        ALL.put("alex", new ForecastProfile("alex", "Alex", 29, "founder", 10,
                new Finances(33_600, 15_600, 0, 4_600, 3_310), new World(0, false, 300, 0, false, false, false),
                habits("monthly_saving", "about €300, irregular", "income", "variable, business and personal mixed",
                        "investing", "invested in 4 of the last 12 months", "crash_reaction", "held in the crash test",
                        "disability_cover", "no, self-employed"),
                List.of(new ForecastGoal("g1", "Build €250k of wealth by age 39", 250_000, 10, 1),
                        new ForecastGoal("g2", "Have €40k of savings by age 31", 40_000, 2, 2)),
                List.of(
                        new PlannedChange("salary", "Pay yourself a fixed €3,200 salary",
                                "Separate accounts and pay a fixed monthly owner's salary, saving €400 of it",
                                "Open the business account and set the €3,200 owner's salary as a standing order.",
                                w -> w.withSaveCash(w.saveCash() + 400)),
                        new PlannedChange("invest", "Invest €400 a month",
                                "Start a €400 monthly savings plan in a broad fund",
                                "Set up the €400 monthly savings plan on the 1st of each month.",
                                w -> w.withSaveInv(w.saveInv() + 400)),
                        new PlannedChange("cover", "Get disability cover", "Put income-protection cover in place as a founder",
                                "Book the 15-minute income protection check for self-employed people.", World::withCover))));

        // ---- Maya, 31, inheritance -------------------------------------------------------------
        ALL.put("maya", new ForecastProfile("maya", "Maya", 31, "heir", 15,
                new Finances(275_500, 5_500, 220_000, 4_200, 3_450), new World(0, false, 300, 0, false, true, false),
                habits("inheritance", "€220k in cash, €50k in an ETF", "idle_cash", "€220k earning almost nothing",
                        "spending", "wants up 38% since the inheritance", "crash_reaction", "sold in the crash test",
                        "monthly_saving", "about €300, irregular", "disability_cover", "no"),
                List.of(new ForecastGoal("g1", "Grow the inheritance to €500k by age 46", 500_000, 15, 1)),
                List.of(
                        new PlannedChange("invest_idle", "Invest the idle cash step by step",
                                "Invest the idle €220k in 12 monthly steps in a balanced portfolio",
                                "Book the inheritance debrief with your advisor to set up the 12-step investment plan.",
                                World::deployingIdle),
                        new PlannedChange("spend_less", "Cap wants at €1,250 a month",
                                "Set a €1,250 monthly limit for wants and save the €500 it frees",
                                "Switch on the €1,250 limit for wants with alerts in the app.",
                                w -> w.withSaveCash(w.saveCash() + 500)),
                        new PlannedChange("hold_rule", "Hold by written rule in a crash",
                                "Follow written rules in a market fall instead of selling",
                                "Write down your rules for a falling market with your advisor, then practise them in the crash review.",
                                World::holding),
                        new PlannedChange("cover", "Get disability cover", "Put income-protection cover in place",
                                "Book the 15-minute income protection check with a specialist.", World::withCover))));
    }

    private static Map<String, String> habits(String... kv) {
        Map<String, String> m = new LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) m.put(kv[i], kv[i + 1]);
        return m;
    }

    public static Optional<ForecastProfile> get(String id) { return Optional.ofNullable(ALL.get(id)); }

    public static List<String> ids() { return List.copyOf(ALL.keySet()); }
}
