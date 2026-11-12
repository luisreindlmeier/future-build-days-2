package com.futurebuild.wealthtree.scanner;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Compact view of a scanner result for the tree.
 * predictedScore is on the CFPB well-being scale (engine range about 16–72.5);
 * percentile ranks it against peers of the same age band (0–100).
 */
public record WellBeing(String ageBand, Double predictedScore, Double percentile,
                        Map<String, Double> dimensions, Map<String, Double> dimensionPercentiles,
                        Double habits, Double habitsPercentile, List<String> missingDimensions, List<String> warnings) {

    public Double dim(String name) { return dimensions.get(name); }

    @SuppressWarnings("unchecked")
    public static WellBeing of(Map<String, Object> r) {
        Map<String, Double> d = new LinkedHashMap<>(), dp = new LinkedHashMap<>();
        ((Map<String, Object>) r.get("dimensions")).forEach((k, v) -> {
            Map<String, Object> m = (Map<String, Object>) v;
            d.put(k, (Double) m.get("score"));
            dp.put(k, (Double) m.get("percentile"));
        });
        Map<String, Object> h = (Map<String, Object>) r.get("habits_display_only");
        return new WellBeing((String) r.get("age_band"), (Double) r.get("predicted_score"), (Double) r.get("predicted_score_percentile"),
                d, dp, (Double) h.get("score"), (Double) h.get("percentile"),
                (List<String>) r.get("missing_dimensions"), (List<String>) r.get("warnings"));
    }
}
