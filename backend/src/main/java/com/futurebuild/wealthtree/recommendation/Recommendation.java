package com.futurebuild.wealthtree.recommendation;

/** Output of the recommendation step: why + what to do (action/product) + what to learn (training). */
public record Recommendation(
        String id,
        Pillar pillar,
        int priority,               // higher = more urgent
        String title,
        String why,
        Action action,
        Training training,
        int predictedScoreGain,     // estimated tree-health points if completed (heuristic)
        Double wellbeingGain        // predicted points on the CFPB well-being scale (scanner what-if); null if not measurable
) {
    public Recommendation withWellbeingGain(Double g) {
        return new Recommendation(id, pillar, priority, title, why, action, training, predictedScoreGain, g);
    }
}
