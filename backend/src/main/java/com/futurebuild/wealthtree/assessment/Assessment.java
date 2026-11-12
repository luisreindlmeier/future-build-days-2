package com.futurebuild.wealthtree.assessment;

import com.futurebuild.wealthtree.model.SpendingCategory;
import java.util.List;
import java.util.Map;

/**
 * Output of the assessment step. Scores are 0..100.
 * Pillars map 1:1 to the tree: savings = roots, invest = trunk, spend = leaves, knowledge = soil.
 */
public record Assessment(
        String userId,
        int overallScore,
        int savingsScore,
        int investScore,
        int spendScore,
        int knowledgeScore,
        double monthlySpend,
        double savingsRate,
        double bufferMonths,
        double wantsShare,
        double investedShare,
        double diversification,
        double largestPositionShare,
        double idleCash,
        Map<SpendingCategory, Double> spendByCategory,
        List<SpendingHabit> habits,
        SituationContext context,
        List<String> findings
) {}
