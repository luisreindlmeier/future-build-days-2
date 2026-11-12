package com.futurebuild.wealthtree.scanner;

import com.futurebuild.wealthtree.recommendation.Recommendation;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Hardcoded questionnaire answers (CFPB PUF codes, see the scanner README) for the demo customers,
 * consistent with DemoData, plus the mapping from a recommended action to the answers it would change.
 */
public final class ScannerAnswers {
    private ScannerAnswers() {}

    private static final String[] FS = {"FS1_1", "FS1_2", "FS1_3", "FS1_4", "FS1_5", "FS1_6", "FS1_7", "FS2_1", "FS2_2", "FS2_3"};
    private static final String[] DEBT = {"MANAGE1_1", "COLLECT", "REJECTED_1", "REJECTED_2", "PRODUSE_1", "PRODUSE_2"};
    private static final String[] PLAN = {"PRODHAVE_4", "PRODHAVE_5", "PRODHAVE_6", "PRODHAVE_2", "AUTOMATED_1", "SCFHORIZON"};
    private static final String[] HABITS = {"SAVEHABIT", "MANAGE1_2", "MANAGE1_4", "PROPPLAN_1", "PROPPLAN_2", "PROPPLAN_3", "PROPPLAN_4", "AUTOMATED_2"};

    private static final Map<String, Map<String, Object>> ALL = new LinkedHashMap<>();

    static {
        // reserves: SAVINGSRANGES (1 $0 … 7 $75k+), ABSORBSHOCK (1–4) | confidence: FS 1–5, GOALCONF 1–4, ACT1_2 1–5, SUBKNOWL1 1–7
        ALL.put("lena", build(24, 4, 2, new int[]{3, 3, 2, 3, 2, 2, 2, 4, 4, 3}, 3, 2, 4,
                new int[]{5, 0, 0, 0, 0, 0}, new int[]{0, 0, 0, 0, 7, 2}, new int[]{3, 2, 3, 3, 3, 3, 2, 0}));
        ALL.put("alex", build(29, 5, 4, new int[]{4, 4, 4, 4, 3, 3, 4, 4, 4, 2}, 3, 3, 5,
                new int[]{4, 0, 1, 0, 0, 0}, new int[]{0, 0, 1, 0, 7, 3}, new int[]{3, 3, 4, 3, 4, 5, 4, 0}));
        ALL.put("maya", build(31, 7, 4, new int[]{3, 4, 2, 3, 2, 2, 3, 4, 5, 4}, 2, 2, 3,
                new int[]{5, 0, 0, 0, 0, 0}, new int[]{1, 0, 1, 0, 0, 2}, new int[]{3, 2, 3, 2, 2, 3, 2, 0}));
        ALL.put("max", build(26, 4, 4, new int[]{3, 3, 3, 3, 3, 2, 3, 4, 4, 3}, 3, 3, 4,
                new int[]{5, 0, 0, 0, 0, 0}, new int[]{0, 0, 1, 0, 7, 4}, new int[]{2, 3, 3, 3, 3, 4, 2, 0}));
    }

    private static Map<String, Object> build(int age, int savingsRange, int absorbShock, int[] fs, int goalConf, int act, int subKnowl,
                                             int[] debt, int[] plan, int[] habits) {
        Map<String, Object> a = new LinkedHashMap<>();
        a.put("age", age);
        a.put("SAVINGSRANGES", savingsRange);
        a.put("ABSORBSHOCK", absorbShock);
        for (int i = 0; i < FS.length; i++) a.put(FS[i], fs[i]);
        a.put("GOALCONF", goalConf);
        a.put("ACT1_2", act);
        a.put("SUBKNOWL1", subKnowl);
        for (int i = 0; i < DEBT.length; i++) a.put(DEBT[i], debt[i]);
        for (int i = 0; i < PLAN.length; i++) a.put(PLAN[i], plan[i]);
        for (int i = 0; i < HABITS.length; i++) a.put(HABITS[i], habits[i]);
        return a;
    }

    public static Optional<Map<String, Object>> get(String userId) {
        Map<String, Object> a = ALL.get(userId);
        if (a == null) a = com.futurebuild.wealthtree.profiles.CustomProfiles.answers(userId).orElse(null);   // created profiles
        return a == null ? Optional.empty() : Optional.of(new LinkedHashMap<>(a));
    }

    /**
     * The answers an action would change once it is done. Assumptions, kept deliberately simple:
     * a buffer moves savings up one band and makes a $2,000 shock manageable; protection = PRODHAVE_2
     * (the survey has no disability item); a pension plan = retirement account + automation;
     * investing = non-retirement investments + automatic saving; spending limits improve
     * "stayed within budget"; a learning module raises self-assessed knowledge by one step.
     */
    public static Map<String, Object> changeFor(Recommendation r, Map<String, Object> current) {
        Map<String, Object> c = new LinkedHashMap<>();
        String id = r.action().id();
        switch (r.action().type()) {
            case AUTO_SAVE, MOVE_CASH -> {
                if (id.equals("act-buffer")) { c.put("SAVINGSRANGES", up(current, "SAVINGSRANGES", 7)); c.put("ABSORBSHOCK", up(current, "ABSORBSHOCK", 4)); }
                if (id.equals("act-retirement")) { c.put("PRODHAVE_4", 1); c.put("AUTOMATED_1", 1); }
            }
            case PROTECT -> c.put("PRODHAVE_2", 1);
            case INVEST_MONTHLY -> { c.put("PRODHAVE_6", 1); c.put("AUTOMATED_2", 1); }
            case SPENDING_LIMIT -> c.put("MANAGE1_2", up(current, "MANAGE1_2", 5));
            case LEARN -> c.put("SUBKNOWL1", up(current, "SUBKNOWL1", 7));
            default -> { }
        }
        return c;
    }

    /** All changes of several actions applied together. */
    public static Map<String, Object> applyAll(Map<String, Object> answers, List<Recommendation> recs) {
        Map<String, Object> a = new LinkedHashMap<>(answers);
        for (Recommendation r : recs) a.putAll(changeFor(r, a));
        return a;
    }

    private static int up(Map<String, Object> a, String key, int max) {
        Object v = a.get(key);
        int cur = v instanceof Number n ? n.intValue() : 0;
        return Math.min(max, cur + 1);
    }
}
