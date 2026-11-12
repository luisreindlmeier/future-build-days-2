package com.futurebuild.wealthtree.model;


import java.util.List;

/**
 * Profile = mix of deterministic data (income, history) and non-deterministic inputs
 * (age, risk tolerance, free-text situation, goals) that the user tells us.
 */
public record UserProfile(
        String id,
        String name,
        int age,
        double netMonthlyIncome,
        RiskTolerance riskTolerance,
        String situation,
        List<String> goals,
        double knowledgeScore,          // 0..1 from the knowledge check
        List<String> completedTrainings,
        int monthsInvestedLast12,       // investment consistency
        int yearsConsistent             // becomes the tree rings
) implements java.io.Serializable {
    public UserProfile withContext(int newAge, RiskTolerance newRisk, String newSituation, List<String> newGoals) {
        return new UserProfile(id, name, newAge, netMonthlyIncome, newRisk, newSituation, newGoals,
                knowledgeScore, completedTrainings, monthsInvestedLast12, yearsConsistent);
    }

    public UserProfile withProgress(double newKnowledge, List<String> trainings, int monthsInvested, int years) {
        return new UserProfile(id, name, age, netMonthlyIncome, riskTolerance, situation, goals,
                newKnowledge, trainings, monthsInvested, years);
    }
}
