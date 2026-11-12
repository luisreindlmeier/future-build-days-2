package com.futurebuild.wealthtree;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.futurebuild.wealthtree.learning.LearningService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.*;

class LearningTest {

    @Test
    void recordsUpdatesAndRemembersMissions(@TempDir Path dir) {
        Path file = dir.resolve("learning.json");
        LearningService s = new LearningService(new ObjectMapper(), file);
        s.record("max", "safety", "Your safety net", "Saving", false);
        s.record("max", "compound", "How money grows", "Investing", true);
        s.record("max", "safety", "Your safety net", "Saving", true);          // done again: replaces, now right
        assertEquals(2, s.list("max").size());
        assertTrue(s.list("max").stream().filter(e -> e.missionId().equals("safety")).findFirst().orElseThrow().correct());
        assertTrue(s.list("maya").isEmpty());

        LearningService again = new LearningService(new ObjectMapper(), file);  // after a restart
        assertEquals(2, again.list("max").size());
        again.clear();
        assertTrue(new LearningService(new ObjectMapper(), file).list("max").isEmpty(), "reset clears it for good");
    }

    @Test
    void rejectsBadInput(@TempDir Path dir) {
        LearningService s = new LearningService(new ObjectMapper(), dir.resolve("l.json"));
        assertThrows(IllegalArgumentException.class, () -> s.record("max", "Bad Id!", "x", "", true));
        assertThrows(IllegalArgumentException.class, () -> s.record("max", "ok", "x".repeat(81), "", true));
    }
}
