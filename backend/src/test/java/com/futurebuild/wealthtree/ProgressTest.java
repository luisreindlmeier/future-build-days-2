package com.futurebuild.wealthtree;

import com.futurebuild.wealthtree.app.WealthTreeService;
import com.futurebuild.wealthtree.assessment.Assessor;
import com.futurebuild.wealthtree.assessment.KeywordSituationInterpreter;
import com.futurebuild.wealthtree.data.InMemoryUserRepository;
import com.futurebuild.wealthtree.progress.ActionStatus;
import com.futurebuild.wealthtree.progress.FileStateStore;
import com.futurebuild.wealthtree.progress.ProgressService;
import com.futurebuild.wealthtree.projection.ProjectionService;
import com.futurebuild.wealthtree.recommendation.RecommendationEngine;
import com.futurebuild.wealthtree.scanner.FinancialHealthScanner;
import com.futurebuild.wealthtree.tree.TreeBuilder;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.*;

class ProgressTest {

    private static ProgressService boot(Path file) {
        Assessor as = new Assessor(new KeywordSituationInterpreter());
        TreeBuilder tb = new TreeBuilder();
        InMemoryUserRepository repo = new InMemoryUserRepository();
        WealthTreeService s = new WealthTreeService(repo, as, new RecommendationEngine(), tb, new ProjectionService(as, tb),
                FinancialHealthScanner.fromClasspath());
        return new ProgressService(s, repo, new FileStateStore(file));
    }

    @Test
    void planGrowsTheTreeAndDoingNothingDoesNot(@TempDir Path dir) {
        ProgressService plan = boot(dir.resolve("plan.ser"));
        for (String a : new String[]{"act-limit-eating_out", "act-limit-shopping", "act-buffer", "act-invest-idle"}) plan.commit("maya", a);
        int withPlan = plan.advance("maya", 6).tree().overallHealth();

        ProgressService nothing = boot(dir.resolve("nothing.ser"));
        int start = nothing.history("maya").snapshots().get(0).treeHealth();
        int without = nothing.advance("maya", 6).tree().overallHealth();

        assertTrue(withPlan > start, "plan should grow the tree");
        assertTrue(withPlan > without, "plan should beat doing nothing");
        assertTrue(plan.history("maya").actions().stream().anyMatch(a -> a.status() == ActionStatus.VERIFIED));
    }

    @Test
    void remembersAcrossRestartsAndResets(@TempDir Path dir) {
        Path file = dir.resolve("state.ser");
        ProgressService first = boot(file);
        first.commit("lena", "act-buffer");
        first.advance("lena", 3);

        ProgressService second = boot(file);                      // "restart"
        assertEquals(4, second.history("lena").snapshots().size());   // start + 3 months
        assertEquals(ActionStatus.VERIFIED, second.history("lena").actions().get(0).status());

        second.reset();
        assertEquals(1, second.history("lena").snapshots().size());
    }
}
