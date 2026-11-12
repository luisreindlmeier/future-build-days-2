package com.futurebuild.wealthtree.api;

import com.futurebuild.wealthtree.progress.ProgressService;
import com.futurebuild.wealthtree.progress.ProgressSummary;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/** Progress over time: commit actions, move time forward, read the history. Saved to a file. */
@RestController
public class ProgressController {

    private final ProgressService progress;

    public ProgressController(ProgressService progress) {
        this.progress = progress;
    }

    /** Commit to a recommended action (use the action id, e.g. "act-limit-eating_out", or the recommendation id). */
    @PostMapping("/api/users/{id}/actions/{actionId}/commit")
    public ProgressSummary commit(@PathVariable String id, @PathVariable String actionId) { return progress.commit(id, actionId); }

    @PostMapping("/api/users/{id}/actions/{actionId}/drop")
    public ProgressSummary drop(@PathVariable String id, @PathVariable String actionId) { return progress.drop(id, actionId); }

    /** Demo time machine: one (or more) months pass. Returns what happened and the new tree. */
    @PostMapping("/api/users/{id}/advance-month")
    public ProgressService.AdvanceResult advance(@PathVariable String id, @RequestParam(defaultValue = "1") int months) {
        return progress.advance(id, months);
    }

    /** All monthly snapshots (tree health, CFPB score, pillars, leaves…), actions and milestones. */
    @GetMapping("/api/users/{id}/history")
    public ProgressService.History history(@PathVariable String id) { return progress.history(id); }

    @GetMapping("/api/users/{id}/progress")
    public ProgressSummary summary(@PathVariable String id) { return progress.summary(id); }

    /** Back to the original demo data for everyone (deletes the saved state). */
    @PostMapping("/api/demo/reset")
    public Map<String, String> reset() {
        progress.reset();
        return Map.of("status", "reset to demo data");
    }
}
