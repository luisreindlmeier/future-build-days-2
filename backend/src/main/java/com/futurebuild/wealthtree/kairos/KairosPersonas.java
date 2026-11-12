package com.futurebuild.wealthtree.kairos;

import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * What the bank data alone doesn't tell the team's engine: profile, purpose, crash reflex,
 * will, base saving habit, goals and subscriptions with their last use. Hardcoded demo data.
 * Max matches the team's EXAMPLE_CUSTOMER / input.txt.
 */
public final class KairosPersonas {
    private KairosPersonas() {}

    public record Subscription(String name, double monthly, int lastUsedDays) {}
    public record Purchase(String label, double amount, int inMonths) {}

    public record Extras(
            String profile,                 // heir | founder | pro
            String purpose,
            String crashReaction,           // sell | hold | buy (reflex test)
            boolean will,
            double baseSavingCash,          // habit before any committed action (€/month)
            double baseSavingInvested,
            Double bufferAmount,            // null -> engine default (10% of income)
            Double investAmount,            // null -> engine default (5% of income)
            int horizonYears,
            List<Map<String, Object>> goals,
            List<Subscription> subscriptions,
            List<Purchase> plannedPurchases,
            String incomeNote
    ) {}

    private static final Map<String, Extras> ALL = Map.of(
            "lena", new Extras("pro", "Security", "hold", false, 150, 0, 250.0, 150.0, 11,
                    List.of(Map.of("type", "wealth", "target", 100_000, "priority", 1)),
                    List.of(new Subscription("Music streaming", 11, 1), new Subscription("Language app", 13, 80),
                            new Subscription("Fitness app", 21, 96)),
                    List.of(), null),
            "alex", new Extras("founder", "Independence", "hold", false, 300, 0, 400.0, 400.0, 10,
                    List.of(Map.of("type", "wealth", "target", 250_000, "priority", 1)),
                    List.of(new Subscription("Design software", 66, 1), new Subscription("Coworking membership", 120, 45),
                            new Subscription("Second cloud storage", 15, 140)),
                    List.of(), "variable income from the new business"),
            "maya", new Extras("heir", "Freedom", "sell", false, 300, 0, null, null, 15,
                    List.of(Map.of("type", "wealth", "target", 500_000, "priority", 1),
                            Map.of("type", "home", "target", 75_000, "years", 2, "priority", 2)),
                    List.of(new Subscription("Streaming bundle", 28, 3), new Subscription("Wine club", 49, 95),
                            new Subscription("Fitness studio", 89, 70)),
                    List.of(), "salary €4,200; inheritance received"),
            "max", new Extras("heir", "Freedom", "sell", false, 180, 0, 400.0, 150.0, 15,
                    List.of(Map.of("type", "wealth", "target", 1_000_000, "priority", 1)),
                    List.of(new Subscription("Gym premium", 59, 74), new Subscription("Streaming bundle", 28, 2),
                            new Subscription("Car-sharing plus", 19, 121)),
                    List.of(new Purchase("New car", 38_000, 6)), "salary €3,000")
    );

    public static Optional<Extras> get(String id) { return Optional.ofNullable(ALL.get(id)); }
}
