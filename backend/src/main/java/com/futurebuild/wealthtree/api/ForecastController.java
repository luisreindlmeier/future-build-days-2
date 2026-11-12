package com.futurebuild.wealthtree.api;

import com.futurebuild.wealthtree.forecast.AgentInputBuilder;
import com.futurebuild.wealthtree.forecast.ForecastProfiles;
import com.futurebuild.wealthtree.prediction.PredictionResult;
import com.futurebuild.wealthtree.prediction.PredictionService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.NoSuchElementException;

/** The team's engine + prediction agent + action agent, fed with each customer's live data. */
@RestController
@RequestMapping("/api/users")
public class ForecastController {

    private final PredictionService predictions;
    private final AgentInputBuilder legacy;

    public ForecastController(PredictionService predictions, AgentInputBuilder legacy) {
        this.predictions = predictions;
        this.legacy = legacy;
    }

    /** The customer intake sent to the team's engine (built live from bank data, Destatis peers and progress). */
    @GetMapping("/{id}/intake")
    public Map<String, Object> intake(@PathVariable String id) { return predictions.intake(id); }

    /** Engine + chart + prediction agent + action agent. RUNNING at first: poll every few seconds. */
    @GetMapping("/{id}/prediction")
    public PredictionResult prediction(@PathVariable String id) { return predictions.get(id); }

    @PostMapping("/{id}/prediction/refresh")
    public PredictionResult refresh(@PathVariable String id) { return predictions.refresh(id); }

    /**
     * Exactly what the projects section reads (intake + engine + prediction_agent + action_agent).
     * Waits up to `wait` seconds. Use it as: index.html?customer=http://localhost:8080/api/users/maya/kairos
     */
    @GetMapping("/{id}/kairos")
    public ResponseEntity<Object> kairos(@PathVariable String id, @RequestParam(defaultValue = "60") long wait) {
        PredictionResult r = predictions.await(id, Math.max(0, Math.min(wait, 120)));
        if (r.status() == PredictionResult.Status.READY) return ResponseEntity.ok(r.kairos());
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(Map.of("status", r.status(), "error", String.valueOf(r.error())));
    }

    /** Offline fallback: the Java port of the demo engine (v1.0 assumptions). Prefer /prediction (chart field). */
    @GetMapping("/{id}/forecast/agent-input")
    public Map<String, Object> legacyAgentInput(@PathVariable String id) {
        return legacy.build(ForecastProfiles.get(id).orElseThrow(() -> new NoSuchElementException("No forecast profile for: " + id)));
    }

    @GetMapping("/{id}/forecast/chart")
    public Object chart(@PathVariable String id) {
        PredictionResult r = predictions.get(id);
        if (r.status() == PredictionResult.Status.READY && r.chart() != null) return r.chart();
        return legacy.chart(ForecastProfiles.get(id).orElseThrow(() -> new NoSuchElementException("No forecast profile for: " + id)));
    }
}
