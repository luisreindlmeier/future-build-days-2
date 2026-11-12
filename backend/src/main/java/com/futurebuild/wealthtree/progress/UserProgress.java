package com.futurebuild.wealthtree.progress;

import java.io.Serializable;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Everything remembered about one user over time. Mutable, guarded by ProgressService. */
public class UserProgress implements Serializable {
    public final String userId;
    public YearMonth month;                                   // the user's current (simulated) month
    public final List<TrackedAction> actions = new ArrayList<>();
    public final List<Snapshot> history = new ArrayList<>();
    public final Map<String, Object> answers = new LinkedHashMap<>();   // current questionnaire answers
    public final Set<String> milestones = new LinkedHashSet<>();         // blossoms, kept forever
    public final List<Boolean> investedMonths = new ArrayList<>();      // rolling window for consistency

    public UserProgress(String userId, YearMonth start, Map<String, Object> answers) {
        this.userId = userId;
        this.month = start;
        this.answers.putAll(answers);
    }
}
