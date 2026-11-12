package com.futurebuild.wealthtree.api;

import com.futurebuild.wealthtree.app.WealthTreeService;
import com.futurebuild.wealthtree.learning.LearningService;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/** Learning missions finished in the app. The advisor view reads them; they do not change scores. */
@RestController
@RequestMapping("/api/users/{id}/learning")
public class LearningController {
    private final LearningService learning;
    private final WealthTreeService tree;

    public LearningController(LearningService learning, WealthTreeService tree) {
        this.learning = learning;
        this.tree = tree;
    }

    public record MissionDone(String missionId, String title, String topic, Boolean correct) {}

    @GetMapping
    public List<LearningService.Entry> list(@PathVariable String id) {
        tree.user(id);                                    // 404 for unknown customers
        return learning.list(id);
    }

    @PostMapping
    public List<LearningService.Entry> record(@PathVariable String id, @RequestBody MissionDone m) {
        tree.user(id);
        return learning.record(id, m.missionId(), m.title(), m.topic(), Boolean.TRUE.equals(m.correct()));
    }
}
