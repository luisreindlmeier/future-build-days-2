package com.futurebuild.wealthtree.api;

import com.futurebuild.wealthtree.app.WealthTreeService;
import com.futurebuild.wealthtree.prediction.KairosBridge;
import com.futurebuild.wealthtree.prediction.PredictionService;
import com.futurebuild.wealthtree.prediction.PredictionResult;
import com.futurebuild.wealthtree.progress.ProgressService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.util.Map;
import java.util.Set;

/** One customer contract for the UI; financial facts are always loaded on the server. */
@RestController
@RequestMapping("/api/users/{id}")
public class WorkspaceController {
    private final WealthTreeService tree;
    private final ProgressService progress;
    private final PredictionService predictions;
    private final KairosBridge bridge;
    private final com.futurebuild.wealthtree.learning.LearningService learning;
    private static final Set<String> TYPES = Set.of("car", "home", "business", "studies", "trip", "family", "sabbatical");

    public WorkspaceController(WealthTreeService tree, ProgressService progress, PredictionService predictions, KairosBridge bridge,
                               com.futurebuild.wealthtree.learning.LearningService learning) {
        this.tree = tree; this.progress = progress; this.predictions = predictions; this.bridge = bridge; this.learning = learning;
    }

    @GetMapping("/workspace")
    public Map<String, Object> workspace(@PathVariable String id) {
        return Map.of("userId", id, "tree", tree.tree(id), "assessment", tree.assessment(id),
                "progress", progress.summary(id), "prediction", predictions.get(id),
                "actionMappings", progress.actionMappings(id), "projects", tree.user(id).projects(),
                "learning", learning.list(id));
    }

    public record ProjectRequest(String type, String name, String description) {}

    @PostMapping("/projects/plan")
    public Map<String, Object> plan(@PathVariable String id, @RequestBody ProjectRequest project) {
        tree.user(id);
        if (project.type() == null || !TYPES.contains(project.type()) || project.description() == null
                || project.description().isBlank() || project.description().length() > 1500
                || (project.name() != null && project.name().length() > 120)) {
            throw new IllegalArgumentException("Supply a supported project type and description (1–1500 characters); name max 120.");
        }
        PredictionResult result = predictions.await(id, 90);
        if (result.status() != PredictionResult.Status.READY) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Assessment not ready; retry shortly.");
        }
        try {
            return bridge.projects(Map.of("assessment", result.kairos(), "project",
                    Map.of("type", project.type(), "name", project.name() == null ? project.type() : project.name(),
                            "description", project.description())));
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Project planner unavailable; check the local bridge.");
        }
    }
}
