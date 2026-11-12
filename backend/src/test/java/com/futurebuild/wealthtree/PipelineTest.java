package com.futurebuild.wealthtree;

import com.futurebuild.wealthtree.app.WealthTreeService;
import com.futurebuild.wealthtree.assessment.Assessor;
import com.futurebuild.wealthtree.assessment.HabitHealth;
import com.futurebuild.wealthtree.assessment.KeywordSituationInterpreter;
import com.futurebuild.wealthtree.data.InMemoryUserRepository;
import com.futurebuild.wealthtree.projection.ProjectionService;
import com.futurebuild.wealthtree.recommendation.RecommendationEngine;
import com.futurebuild.wealthtree.tree.TreeBuilder;
import com.futurebuild.wealthtree.tree.TreeState;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/** Core pipeline tests: no Spring context needed. */
class PipelineTest {

    private final Assessor assessor = new Assessor(new KeywordSituationInterpreter());
    private final TreeBuilder treeBuilder = new TreeBuilder();
    private final WealthTreeService service = new WealthTreeService(new InMemoryUserRepository(), assessor,
            new RecommendationEngine(), treeBuilder, new ProjectionService(assessor, treeBuilder));

    @Test
    void mayaHasRottenLeavesAndInheritanceAdvice() {
        TreeState t = service.tree("maya");
        assertTrue(t.leaves().stream().anyMatch(l -> l.health() == HabitHealth.ROTTEN));
        assertEquals(4, t.roots().size());
        assertTrue(service.recommendations("maya").stream().anyMatch(r -> r.id().equals("rec-inheritance")));
    }

    @Test
    void followingThePlanGrowsTheTree() {
        for (String id : List.of("lena", "alex", "maya")) {
            var all = service.simulate(id, null, 12);
            var nothing = service.simulate(id, List.of(), 12);
            assertTrue(all.scoreAfter() > nothing.scoreAfter(), id + " should improve with the plan");
        }
    }

    @Test
    void leavesAreJudgedAgainstDestatisPeers() {
        // Maya: €4,200 net income -> class €3,600–5,000; peers spend €226 a month on eating out (LWR 2024)
        var eatingOut = service.assessment("maya").habits().stream()
                .filter(h -> h.category() == com.futurebuild.wealthtree.model.SpendingCategory.EATING_OUT).findFirst().orElseThrow();
        assertEquals(226, eatingOut.peerAverage(), 0.01);
        assertEquals(HabitHealth.ROTTEN, eatingOut.health());
        assertTrue(eatingOut.peerGroup().contains("Destatis"));
    }

    @Test
    void alexIsWindy() {
        assertEquals("WINDY", service.tree("alex").weather().type().name());
    }
}
