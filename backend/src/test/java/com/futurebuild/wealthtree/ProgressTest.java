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
    void agentAliasesCommitVerifyAndDropCanonicalActions(@TempDir Path dir) {
        ProgressService progress = boot(dir.resolve("aliases.ser"));
        var mapping = progress.actionMappings("maya").get("limit_eating_out");
        assertTrue(mapping.canCommit());
        assertEquals("act-limit-eating_out", mapping.action().id());
        progress.commit("maya", "limit_eating_out");
        progress.commit("maya", "act-limit-eating_out");
        assertEquals(1, progress.history("maya").actions().size());
        assertEquals(mapping.action().monthlyAmount(), progress.history("maya").actions().get(0).monthlyAmount());
        progress.advance("maya", 3);
        assertEquals(ActionStatus.VERIFIED, progress.history("maya").actions().get(0).status());
        progress.drop("maya", "limit_eating_out");
        assertEquals(ActionStatus.DROPPED, progress.history("maya").actions().get(0).status());
    }

    @Test
    void unsupportedAndUnavailableAgentActionsCannotCommit(@TempDir Path dir) {
        ProgressService progress = boot(dir.resolve("unavailable.ser"));
        assertFalse(progress.actionMappings("maya").get("write_will").canCommit());
        assertThrows(java.util.NoSuchElementException.class, () -> progress.commit("maya", "write_will"));
        assertThrows(java.util.NoSuchElementException.class, () -> progress.commit("maya", "limit_invented"));
        progress.commit("maya", "income_protection_check");
        progress.advance("maya", 3);
        assertFalse(progress.actionMappings("maya").get("income_protection_check").canCommit());
        assertThrows(java.util.NoSuchElementException.class, () -> progress.commit("maya", "income_protection_check"));
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
