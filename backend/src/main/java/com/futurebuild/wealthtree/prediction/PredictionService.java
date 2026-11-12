package com.futurebuild.wealthtree.prediction;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;

/**
 * Runs the team's pipeline in the background and caches it per customer. The cache key is the intake
 * itself: when the customer's data changes (a month passes, an action is verified), the next request
 * starts a fresh run, so predictions follow the tree.
 */
public class PredictionService {

    private record Entry(Map<String, Object> intake, CompletableFuture<PredictionResult> future) {}

    private static final long RETRY_SECONDS = 10;

    private final Function<String, Map<String, Object>> intakes;
    private final Function<String, String> names;
    private final KairosBridge bridge;
    private final ExecutorService pool = Executors.newFixedThreadPool(4);
    private final Map<String, Entry> cache = new ConcurrentHashMap<>();
    private final Map<String, PredictionResult> lastReady = new ConcurrentHashMap<>();

    /** names: real first name for the projects section (the AI only ever sees "Customer"). */
    public PredictionService(Function<String, Map<String, Object>> intakes, Function<String, String> names, KairosBridge bridge) {
        this.intakes = intakes;
        this.names = names;
        this.bridge = bridge;
    }

    public Map<String, Object> intake(String id) {
        return intakes.apply(id);
    }

    /** Never blocks. */
    public PredictionResult get(String id) {
        Map<String, Object> intake = intakes.apply(id);
        Entry e = cache.compute(id, (k, old) -> {
            if (old != null && old.intake().equals(intake)) {
                if (!old.future().isDone()) return old;
                PredictionResult r = old.future().join();
                boolean retry = r.status() == PredictionResult.Status.UNAVAILABLE
                        && r.updatedAt().isBefore(Instant.now().minusSeconds(RETRY_SECONDS));
                if (!retry) return old;
            }
            return new Entry(intake, start(id, intake));
        });
        if (e.future().isDone()) {
            PredictionResult r = e.future().join();
            if (r.status() == PredictionResult.Status.READY) lastReady.put(id, r);
            return r;
        }
        // While a fresh run is in progress (e.g. after a demo month), keep serving the previous
        // coaching so the dashboard does not go blank; status RUNNING tells clients to keep polling.
        PredictionResult prev = lastReady.get(id);
        if (prev != null) {
            return new PredictionResult(id, PredictionResult.Status.RUNNING, intake, prev.engine(), prev.chart(),
                    prev.prediction(), prev.actions(), prev.kairos(), null, prev.updatedAt());
        }
        return new PredictionResult(id, PredictionResult.Status.RUNNING, intake, null, null, null, null, null, null, Instant.now());
    }

    /** Waits up to `seconds` for the result (for clients that can't poll, like the projects section). */
    public PredictionResult await(String id, long seconds) {
        get(id);
        try {
            return cache.get(id).future().get(seconds, TimeUnit.SECONDS);
        } catch (Exception e) {
            return get(id);
        }
    }

    public PredictionResult refresh(String id) {
        cache.remove(id);
        return get(id);
    }

    public void warmUp(List<String> ids) {
        ids.forEach(this::get);
    }

    @SuppressWarnings("unchecked")
    private CompletableFuture<PredictionResult> start(String id, Map<String, Object> intake) {
        return CompletableFuture.supplyAsync(() -> {
            try {
                Map<String, Object> r = bridge.assessment(intake);
                Object kairos = r.get("kairos");
                if (kairos instanceof Map<?, ?> k && k.get("intake") instanceof Map<?, ?> ki) {   // show the real first name in the app
                    Map<String, Object> km = new LinkedHashMap<>((Map<String, Object>) k);
                    Map<String, Object> named = new LinkedHashMap<>((Map<String, Object>) ki);
                    named.put("name", names.apply(id));
                    km.put("intake", named);
                    kairos = km;
                }
                return new PredictionResult(id, PredictionResult.Status.READY, intake, r.get("engine"), r.get("chart"),
                        r.get("prediction"), r.get("actions"), kairos, null, Instant.now());
            } catch (Exception ex) {
                return new PredictionResult(id, PredictionResult.Status.UNAVAILABLE, intake, null, null, null, null, null,
                        "Kairos bridge not reachable. In the prediction-agent folder run: python kairos_server.py ("
                                + ex.getClass().getSimpleName() + ")", Instant.now());
            }
        }, pool);
    }
}
