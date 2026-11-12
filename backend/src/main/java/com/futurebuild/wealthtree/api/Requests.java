package com.futurebuild.wealthtree.api;

import com.futurebuild.wealthtree.model.RiskTolerance;
import java.time.LocalDate;
import java.util.List;

/** Request bodies. */
public final class Requests {
    private Requests() {}

    /** actionIds: ids of actions or recommendations to apply. Omit (null) to apply all; [] = do nothing. */
    public record Simulate(List<String> actionIds, Integer months) {}

    /** Non-deterministic inputs. Any null field is left unchanged. */
    public record Context(Integer age, RiskTolerance riskTolerance, String situation, List<String> goals) {}

    public record ProjectInput(String id, String name, String type, double targetAmount, double savedAmount, LocalDate targetDate) {}
}
