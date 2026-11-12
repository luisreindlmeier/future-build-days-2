package com.futurebuild.wealthtree.recommendation;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Semantic aliases only. The current backend recommendation owns amounts and verification. */
public final class AgentActionMapping {
    private AgentActionMapping() {}

    private static final Map<String, String> ALIASES = Map.ofEntries(
            Map.entry("start_buffer", "act-buffer"),
            Map.entry("save_more_tomorrow", "act-savings-plan"),
            Map.entry("family_diversification_plan", "act-diversify"),
            Map.entry("income_protection_check", "act-protect"),
            Map.entry("limit_eating_out", "act-limit-eating_out"),
            Map.entry("limit_shopping", "act-limit-shopping"),
            Map.entry("limit_travel", "act-limit-travel"),
            Map.entry("limit_subscriptions", "act-limit-subscriptions"),
            Map.entry("limit_other", "act-limit-other"));

    public static String canonicalId(String id) {
        return ALIASES.getOrDefault(id, id);
    }

    public record Mapping(String backendActionId, boolean canCommit, Action action, String reason) {}

    public static Map<String, Mapping> describe(List<Recommendation> recommendations) {
        Map<String, Mapping> out = new LinkedHashMap<>();
        ALIASES.entrySet().stream().sorted(Map.Entry.comparingByKey()).forEach(e -> {
            Action action = recommendations.stream().map(Recommendation::action)
                    .filter(a -> a.id().equals(e.getValue())).findFirst().orElse(null);
            out.put(e.getKey(), new Mapping(e.getValue(), action != null, action,
                    action == null ? "No matching recommendation is currently available for this customer." : null));
        });
        for (String id : List.of("cancel_unused_subscriptions", "pause_purchase", "close_spending_gap",
                "write_crash_rules", "write_will")) {
            out.put(id, new Mapping(null, false, null, "This action has no equivalent tree action."));
        }
        return out;
    }
}
