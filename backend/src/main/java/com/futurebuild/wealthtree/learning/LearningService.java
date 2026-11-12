package com.futurebuild.wealthtree.learning;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/**
 * Learning missions a customer finished in the app (Learn & grow), so the advisor can see what they learned
 * and which quiz answers went wrong. Kept separate from the scores: finishing a mission does not change the
 * tree's numbers. Saved to a JSON file next to the progress memory.
 */
public class LearningService {

    /** One finished mission. correct = the quiz answer was right on the last attempt. */
    public record Entry(String missionId, String title, String topic, boolean correct, long at) {}

    private final Map<String, List<Entry>> data = new TreeMap<>();
    private final ObjectMapper json;
    private final Path file;

    public LearningService(ObjectMapper json, Path file) {
        this.json = json;
        this.file = file;
        load();
    }

    public synchronized List<Entry> list(String userId) {
        return List.copyOf(data.getOrDefault(userId, List.of()));
    }

    /** Record (or update) a finished mission. Returns the customer's full list. */
    public synchronized List<Entry> record(String userId, String missionId, String title, String topic, boolean correct) {
        if (missionId == null || !missionId.matches("[a-z][a-z0-9_-]{0,29}")) {
            throw new IllegalArgumentException("missionId must be 1-30 lowercase letters, digits, - or _.");
        }
        String t = title == null ? missionId : title.strip();
        if (t.isEmpty() || t.length() > 80) throw new IllegalArgumentException("title must be 1-80 characters.");
        String tp = topic == null ? "" : topic.strip();
        if (tp.length() > 30) throw new IllegalArgumentException("topic must be at most 30 characters.");
        List<Entry> list = new ArrayList<>(data.getOrDefault(userId, List.of()));
        list.removeIf(e -> e.missionId().equals(missionId));
        if (list.size() >= 50) throw new IllegalArgumentException("Too many missions for one customer.");
        list.add(new Entry(missionId, t, tp, correct, System.currentTimeMillis()));
        data.put(userId, list);
        save();
        return List.copyOf(list);
    }

    public synchronized void clear(String userId) {
        if (data.remove(userId) != null) save();
    }

    public synchronized void clear() {
        data.clear();
        save();
    }

    private void load() {
        if (file == null || !Files.exists(file)) return;
        try {
            data.putAll(json.readValue(file.toFile(), new TypeReference<Map<String, List<Entry>>>() {}));
        } catch (IOException e) {
            System.err.println("Could not read " + file + ": " + e.getMessage());
        }
    }

    private void save() {
        if (file == null) return;
        try {
            if (file.getParent() != null) Files.createDirectories(file.getParent());
            Path tmp = file.resolveSibling(file.getFileName() + ".tmp");
            json.writerWithDefaultPrettyPrinter().writeValue(tmp.toFile(), data);
            Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            System.err.println("Could not save " + file + ": " + e.getMessage());
        }
    }
}
