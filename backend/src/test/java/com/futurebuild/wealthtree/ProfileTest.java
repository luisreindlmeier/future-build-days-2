package com.futurebuild.wealthtree;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.futurebuild.wealthtree.app.WealthTreeService;
import com.futurebuild.wealthtree.assessment.Assessor;
import com.futurebuild.wealthtree.assessment.KeywordSituationInterpreter;
import com.futurebuild.wealthtree.data.InMemoryUserRepository;
import com.futurebuild.wealthtree.kairos.IntakeBuilder;
import com.futurebuild.wealthtree.prediction.PredictionService;
import com.futurebuild.wealthtree.profiles.CustomProfiles;
import com.futurebuild.wealthtree.profiles.ProfileRequest;
import com.futurebuild.wealthtree.profiles.ProfileService;
import com.futurebuild.wealthtree.progress.FileStateStore;
import com.futurebuild.wealthtree.progress.ProgressService;
import com.futurebuild.wealthtree.projection.ProjectionService;
import com.futurebuild.wealthtree.recommendation.RecommendationEngine;
import com.futurebuild.wealthtree.scanner.FinancialHealthScanner;
import com.futurebuild.wealthtree.tree.TreeBuilder;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class ProfileTest {

    private record Boot(InMemoryUserRepository repo, WealthTreeService tree, ProgressService progress, IntakeBuilder intakes,
                        ProfileService profiles) {}

    private static Boot boot(Path dir) {
        Assessor as = new Assessor(new KeywordSituationInterpreter());
        TreeBuilder tb = new TreeBuilder();
        InMemoryUserRepository repo = new InMemoryUserRepository();
        WealthTreeService s = new WealthTreeService(repo, as, new RecommendationEngine(), tb, new ProjectionService(as, tb),
                FinancialHealthScanner.fromClasspath());
        ProgressService progress = new ProgressService(s, repo, new FileStateStore(dir.resolve("state.ser")));
        IntakeBuilder intakes = new IntakeBuilder(s);
        PredictionService predictions = new PredictionService(intakes::build, id -> s.user(id).profile().name(),
                in -> Map.of("kairos", Map.of()));
        return new Boot(repo, s, progress, intakes,
                new ProfileService(repo, predictions, progress, new ObjectMapper(), dir.resolve("profiles.json")));
    }

    static ProfileRequest sophie() {
        return new ProfileRequest("Sophie", 33, "pro", "A home of my own", "I work as a nurse and want to buy a flat.",
                "BALANCED", 3600.0, null,
                Map.of("HOUSING", 1100.0, "GROCERIES", 380.0, "EATING_OUT", 420.0, "SUBSCRIPTIONS", 60.0),
                8_000.0, 12_000.0, 0.0, 300.0, 100.0, "sell", false, false, 3, 4, 2, 15,
                List.of(new ProfileRequest.Goal("home", 60_000.0, 6, 1), new ProfileRequest.Goal("wealth", 300_000.0, null, 2)),
                List.of(new ProfileRequest.Subscription("Yoga studio", 49.0, 90), new ProfileRequest.Subscription("Music", 11.0, 1)),
                List.of());
    }

    @AfterEach
    void clean() {
        CustomProfiles.requests().keySet().forEach(CustomProfiles::remove);
    }

    @Test
    void createdProfileWorksInEveryPartOfThePipeline(@TempDir Path dir) {
        Boot b = boot(dir);
        String id = b.profiles().create(sophie()).id();
        assertTrue(id.startsWith("p-sophie-"));
        assertEquals("Sophie", b.tree().user(id).profile().name());
        assertNotNull(b.tree().tree(id), "tree");
        assertNotNull(b.progress().summary(id), "progress");
        assertFalse(b.progress().actionMappings(id).isEmpty(), "action mappings");
        Map<String, Object> in = b.intakes().build(id);
        assertEquals("pro", in.get("profile"));
        assertEquals("sell", in.get("crash_reaction"));
        assertEquals(20_000L, ((Number) in.get("wealth_total")).longValue());
        assertTrue(b.profiles().list().stream().anyMatch(p -> p.id().equals(id) && p.custom()));
    }

    @Test
    void personaliseChangesTheDataAndDemoCustomersAreReadOnly(@TempDir Path dir) {
        Boot b = boot(dir);
        String id = b.profiles().create(sophie()).id();
        ProfileRequest f = b.profiles().form(id);
        ProfileRequest changed = new ProfileRequest(f.name(), 34, f.lifeStage(), f.purpose(), f.situation(), f.riskTolerance(),
                4200.0, f.incomeNote(), f.spending(), f.cashSavings(), f.investments(), f.companyShares(), f.monthlySavingCash(),
                f.monthlySavingInvested(), "hold", true, true, f.confidence(), f.knowledge(), f.shockAbsorb(), f.horizonYears(),
                f.goals(), f.subscriptions(), f.plannedPurchases());
        b.profiles().update(id, changed);
        Map<String, Object> in = b.intakes().build(id);
        assertEquals("hold", in.get("crash_reaction"));
        assertEquals(true, in.get("disability_cover"));
        assertEquals(34, in.get("age"));
        assertThrows(IllegalArgumentException.class, () -> b.profiles().update("maya", changed));
        assertEquals("Maya", b.profiles().form("maya").name(), "demo customers can be read to copy them");
    }

    @Test
    void profilesSurviveARestartAndDelete(@TempDir Path dir) {
        String id = boot(dir).profiles().create(sophie()).id();
        CustomProfiles.remove(id);                               // simulate a fresh process
        Boot again = boot(dir);
        assertEquals("Sophie", again.tree().user(id).profile().name());
        again.profiles().delete(id);
        assertTrue(again.repo().findById(id).isEmpty());
        assertTrue(boot(dir).repo().findById(id).isEmpty(), "deleted for good");
    }

    @Test
    void progressSurvivesARestartForACreatedProfile(@TempDir Path dir) {
        Boot b = boot(dir);
        String id = b.profiles().create(sophie()).id();
        b.progress().advance(id, 2);
        java.time.YearMonth month = b.progress().summary(id).month();
        CustomProfiles.remove(id);
        Boot again = boot(dir);
        assertEquals(month, again.progress().summary(id).month(), "months advanced are remembered");
    }

    @Test
    void invalidInputIsRejectedWithAReason() {
        ProfileRequest s = sophie();
        ProfileRequest noGoal = new ProfileRequest(s.name(), s.age(), s.lifeStage(), s.purpose(), s.situation(), s.riskTolerance(),
                s.monthlyIncome(), null, s.spending(), s.cashSavings(), s.investments(), s.companyShares(), s.monthlySavingCash(),
                s.monthlySavingInvested(), s.crashReaction(), false, false, 3, 4, 2, 15, List.of(), List.of(), List.of());
        IllegalArgumentException e = assertThrows(IllegalArgumentException.class, noGoal::validated);
        assertTrue(e.getMessage().contains("goal"));
        ProfileRequest child = new ProfileRequest(s.name(), 12, s.lifeStage(), s.purpose(), s.situation(), s.riskTolerance(),
                s.monthlyIncome(), null, s.spending(), s.cashSavings(), s.investments(), s.companyShares(), s.monthlySavingCash(),
                s.monthlySavingInvested(), s.crashReaction(), false, false, 3, 4, 2, 15, s.goals(), List.of(), List.of());
        assertThrows(IllegalArgumentException.class, child::validated);
    }
}
