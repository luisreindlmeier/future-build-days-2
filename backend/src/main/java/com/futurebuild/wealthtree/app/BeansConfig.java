package com.futurebuild.wealthtree.app;

import com.futurebuild.wealthtree.assessment.Assessor;
import com.futurebuild.wealthtree.assessment.KeywordSituationInterpreter;
import com.futurebuild.wealthtree.assessment.SituationInterpreter;
import com.futurebuild.wealthtree.data.InMemoryUserRepository;
import com.futurebuild.wealthtree.data.UserRepository;
import com.futurebuild.wealthtree.projection.ProjectionService;
import com.futurebuild.wealthtree.recommendation.RecommendationEngine;
import com.futurebuild.wealthtree.scanner.FinancialHealthScanner;
import com.futurebuild.wealthtree.progress.FileStateStore;
import com.futurebuild.wealthtree.progress.ProgressService;
import com.futurebuild.wealthtree.progress.StateStore;
import com.futurebuild.wealthtree.tree.TreeBuilder;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.futurebuild.wealthtree.forecast.AgentInputBuilder;
import com.futurebuild.wealthtree.forecast.Assumptions;
import com.futurebuild.wealthtree.forecast.MonteCarloEngine;
import com.futurebuild.wealthtree.kairos.IntakeBuilder;
import com.futurebuild.wealthtree.prediction.HttpKairosBridge;
import com.futurebuild.wealthtree.prediction.KairosBridge;
import com.futurebuild.wealthtree.prediction.PredictionService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.nio.file.Path;
import java.time.Duration;

/** Wires the framework-free core. Swap SituationInterpreter for an LLM-backed one later. */
@Configuration
public class BeansConfig {
    @Bean UserRepository userRepository() { return new InMemoryUserRepository(); }
    @Bean SituationInterpreter situationInterpreter() { return new KeywordSituationInterpreter(); }
    @Bean Assessor assessor(SituationInterpreter i) { return new Assessor(i); }
    @Bean RecommendationEngine recommendationEngine() { return new RecommendationEngine(); }
    @Bean TreeBuilder treeBuilder() { return new TreeBuilder(); }
    @Bean ProjectionService projectionService(Assessor a, TreeBuilder t) { return new ProjectionService(a, t); }
    @Bean FinancialHealthScanner financialHealthScanner() { return FinancialHealthScanner.fromClasspath(); }
    @Bean WealthTreeService wealthTreeService(UserRepository r, Assessor a, RecommendationEngine e, TreeBuilder t, ProjectionService p,
                                              FinancialHealthScanner s) {
        return new WealthTreeService(r, a, e, t, p, s);
    }

    // ---- Forecast engine + prediction agent -------------------------------------------------
    @Bean MonteCarloEngine monteCarloEngine() { return new MonteCarloEngine(Assumptions.DEMO); }
    @Bean AgentInputBuilder agentInputBuilder(MonteCarloEngine e) { return new AgentInputBuilder(e); }
    @Bean IntakeBuilder intakeBuilder(WealthTreeService s) { return new IntakeBuilder(s); }
    @Bean KairosBridge kairosBridge(ObjectMapper json,
                                    @Value("${wealthtree.agent.url:http://localhost:8090}") String url,
                                    @Value("${wealthtree.agent.timeout-seconds:90}") long timeout) {
        return new HttpKairosBridge(json, url, Duration.ofSeconds(timeout));
    }
    @Bean PredictionService predictionService(IntakeBuilder intakes, WealthTreeService s, KairosBridge bridge) {
        return new PredictionService(intakes::build, id -> s.user(id).profile().name(), bridge);
    }

    /** Run the team's pipeline for every demo customer at startup, so answers are ready before the pitch. */
    @Bean ApplicationRunner warmUpPredictions(PredictionService p, ProgressService progress, UserRepository repo,
                                              @Value("${wealthtree.agent.warmup:true}") boolean on) {
        return args -> { if (on) p.warmUp(repo.findAll().stream().map(u -> u.profile().id()).toList()); };
    }

    // ---- Memory: progress over time, saved to a file ---------------------------------------------
    @Bean StateStore stateStore(@Value("${wealthtree.state-file:data/wealth-tree-state.ser}") String file) {
        return new FileStateStore(Path.of(file));
    }
    @Bean ProgressService progressService(WealthTreeService s, UserRepository r, StateStore store) {
        return new ProgressService(s, r, store);
    }
}
