package com.futurebuild.wealthtree;

import com.futurebuild.wealthtree.scanner.FinancialHealthScanner;
import com.futurebuild.wealthtree.scanner.MiniJson;
import org.junit.jupiter.api.Test;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import static org.junit.jupiter.api.Assertions.*;

/** The Java scanner must give the same output as the team's score.py for every case in test_cases.json. */
class ScannerParityTest {

    private final FinancialHealthScanner scanner = FinancialHealthScanner.fromClasspath();

    @SuppressWarnings("unchecked")
    private static Map<String, Object> testCases() throws Exception {
        try (InputStream in = ScannerParityTest.class.getResourceAsStream("/scanner/test_cases.json")) {
            return (Map<String, Object>) MiniJson.parse(new String(Objects.requireNonNull(in).readAllBytes(), StandardCharsets.UTF_8));
        }
    }

    private static void same(Object a, Object b, String p) {
        if (a instanceof Map<?, ?> ma) {
            Map<?, ?> mb = (Map<?, ?>) b;
            assertEquals(ma.keySet(), mb.keySet(), p + ": keys");
            for (Object k : ma.keySet()) same(ma.get(k), mb.get(k), p + "." + k);
        } else if (a instanceof List<?> la) {
            List<?> lb = (List<?>) b;
            assertEquals(la.size(), lb.size(), p + ": length");
            for (int i = 0; i < la.size(); i++) same(la.get(i), lb.get(i), p + "[" + i + "]");
        } else if (a instanceof Number x && b instanceof Number y) {
            assertEquals(x.doubleValue(), y.doubleValue(), 1e-9, p);
        } else {
            assertEquals(a, b, p);
        }
    }

    @Test
    @SuppressWarnings("unchecked")
    void matchesScorePy() throws Exception {
        Map<String, Object> t = testCases();
        for (Object o : (List<Object>) t.get("cases")) {
            Map<String, Object> c = (Map<String, Object>) o;
            same(scanner.score((Map<String, Object>) c.get("answers")), c.get("expected"), (String) c.get("name"));
        }
        for (Object o : (List<Object>) t.get("what_if")) {
            Map<String, Object> c = (Map<String, Object>) o;
            same(scanner.whatIf((Map<String, Object>) c.get("baseline"), (Map<String, Object>) c.get("change")), c.get("expected"), (String) c.get("name"));
        }
    }
}
