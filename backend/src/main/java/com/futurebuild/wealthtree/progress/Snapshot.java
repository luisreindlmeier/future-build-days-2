package com.futurebuild.wealthtree.progress;

import java.io.Serializable;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;

/** The tree's vital signs for one month. Scores are derived; snapshots are the memory. */
public record Snapshot(
        YearMonth month,
        int treeHealth,                 // tree's overall health (CFPB peer percentile when scanned)
        Double cfpbScore,               // predicted CFPB well-being score
        int savingsScore, int investScore, int spendScore, int knowledgeScore,
        double bufferMonths, double savingsRate, double wantsShare,
        double liquidSavings, double invested, double netWorth,
        Map<String, String> leafHealth, // category -> HEALTHY / WILTING / ROTTEN
        Map<String, Double> leafSpend,  // category -> € this month
        int rings,
        String headline,
        List<String> events             // what happened this month, in plain words
) implements Serializable {}
