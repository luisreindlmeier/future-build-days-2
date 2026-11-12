package com.futurebuild.wealthtree.assessment;

import com.futurebuild.wealthtree.model.RiskTolerance;
import java.util.List;
import java.util.Set;

/** Interpreted non-deterministic inputs: age, risk, situation text and goals. */
public record SituationContext(LifeStage lifeStage, RiskTolerance risk, Set<SituationFlag> flags, List<String> goals) {
    public boolean has(SituationFlag f) { return flags.contains(f); }
}
