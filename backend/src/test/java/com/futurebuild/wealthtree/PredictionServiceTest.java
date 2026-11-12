package com.futurebuild.wealthtree;

import com.futurebuild.wealthtree.prediction.PredictionResult;
import com.futurebuild.wealthtree.prediction.PredictionService;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class PredictionServiceTest {

    private static PredictionResult waitFor(PredictionService s, String id) throws InterruptedException {
        for (int i = 0; i < 100; i++) {
            PredictionResult r = s.get(id);
            if (r.status() != PredictionResult.Status.RUNNING) return r;
            Thread.sleep(20);
        }
        return s.get(id);
    }

    @Test
    void returnsThePipelineResultWithTheRealName() throws Exception {
        Map<String, Object> intake = new HashMap<>(Map.of("name", "Customer", "age", 31));
        PredictionService s = new PredictionService(id -> intake, id -> "Maya",
                in -> Map.of("engine", Map.of(), "chart", Map.of(), "prediction", Map.of("source", "fallback"),
                        "actions", Map.of(), "kairos", Map.of("intake", Map.of("name", "Customer"))));
        PredictionResult r = waitFor(s, "maya");
        assertEquals(PredictionResult.Status.READY, r.status());
        assertEquals("Maya", ((Map<?, ?>) ((Map<?, ?>) r.kairos()).get("intake")).get("name"));
    }

    @Test
    void newDataStartsANewRun() throws Exception {
        int[] calls = {0};
        Map<String, Object> intake = new HashMap<>(Map.of("cash", 1000));
        PredictionService s = new PredictionService(id -> new HashMap<>(intake), id -> "Lena",
                in -> { calls[0]++; return Map.of("kairos", Map.of()); });
        waitFor(s, "lena");
        waitFor(s, "lena");
        assertEquals(1, calls[0], "same data: cached");
        intake.put("cash", 2000);                                 // a month passed
        waitFor(s, "lena");
        assertEquals(2, calls[0], "changed data: fresh run");
    }

    @Test
    void bridgeDownStillGivesTheIntake() throws Exception {
        PredictionService s = new PredictionService(id -> Map.of("age", 24), id -> "Lena",
                in -> { throw new java.net.ConnectException("down"); });
        PredictionResult r = waitFor(s, "lena");
        assertEquals(PredictionResult.Status.UNAVAILABLE, r.status());
        assertNotNull(r.intake());
        assertTrue(r.error().contains("kairos_server.py"));
    }
}
