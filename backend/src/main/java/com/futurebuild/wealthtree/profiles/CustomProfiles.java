package com.futurebuild.wealthtree.profiles;

import com.futurebuild.wealthtree.kairos.KairosPersonas;
import com.futurebuild.wealthtree.model.UserData;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Registry of the profiles customers created themselves. The demo personas live in static classes
 * (DemoData, KairosPersonas, ScannerAnswers); those classes fall back to this registry, so every
 * existing endpoint (tree, scanner, progress, predictions, actions) works for a created profile too.
 */
public final class CustomProfiles {
    private CustomProfiles() {}

    public record Entry(ProfileRequest request, UserData data, KairosPersonas.Extras extras, Map<String, Object> answers) {}

    private static final Map<String, Entry> ALL = new ConcurrentHashMap<>();

    public static void put(String id, Entry e) { ALL.put(id, e); }
    public static void remove(String id) { ALL.remove(id); }
    public static boolean has(String id) { return ALL.containsKey(id); }
    public static Optional<Entry> get(String id) { return Optional.ofNullable(ALL.get(id)); }
    public static Optional<KairosPersonas.Extras> extras(String id) { return get(id).map(Entry::extras); }
    public static Optional<Map<String, Object>> answers(String id) { return get(id).map(Entry::answers); }
    public static Collection<UserData> data() { return List.copyOf(ALL.values().stream().map(Entry::data).toList()); }
    public static Map<String, ProfileRequest> requests() {
        Map<String, ProfileRequest> out = new java.util.TreeMap<>();
        ALL.forEach((k, v) -> out.put(k, v.request()));
        return out;
    }
}
