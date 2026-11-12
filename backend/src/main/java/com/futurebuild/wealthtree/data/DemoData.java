package com.futurebuild.wealthtree.data;

import com.futurebuild.wealthtree.model.AssetClass;
import com.futurebuild.wealthtree.model.Holding;
import com.futurebuild.wealthtree.model.Project;
import com.futurebuild.wealthtree.model.RiskTolerance;
import com.futurebuild.wealthtree.model.SavingsCategory;
import com.futurebuild.wealthtree.model.SavingsPot;
import com.futurebuild.wealthtree.model.SpendingCategory;
import com.futurebuild.wealthtree.model.Transaction;
import com.futurebuild.wealthtree.model.UserData;
import com.futurebuild.wealthtree.model.UserProfile;

import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static com.futurebuild.wealthtree.model.SpendingCategory.*;

/** The three personas from the challenge brief plus Max from the team demo. All figures are demo data. */
public final class DemoData {
    private DemoData() {}

    public static List<UserData> all() {
        return List.of(lena(), alex(), maya(), max());
    }

    static UserData lena() {
        UserProfile p = new UserProfile("lena", "Lena", 24, 2900, RiskTolerance.BALANCED,
                "I just got my first salary after graduating. Stable income but I save irregularly.",
                List.of("Build a safety buffer", "Trip to Japan"), 0.5, List.of(), 0, 0);
        return new UserData(p,
                List.of(new SavingsPot("lena-emergency", SavingsCategory.EMERGENCY, "Savings account", 900, 0)),
                List.of(new Holding("Current account surplus", AssetClass.CASH, 1200)),
                spending(Map.of(HOUSING, new double[]{950, 950}, GROCERIES, new double[]{320, 340}, TRANSPORT, new double[]{120, 120},
                        EATING_OUT, new double[]{300, 460}, SHOPPING, new double[]{220, 260}, SUBSCRIPTIONS, new double[]{45, 45})),
                List.of(new Project("japan", "Trip to Japan", "TRAVEL", 4000, 300, YearMonth.now().plusMonths(14).atDay(1))));
    }

    static UserData alex() {
        UserProfile p = new UserProfile("alex", "Alex", 29, 4600, RiskTolerance.GROWTH,
                "I'm starting a business. Variable income, and personal and business finances are mixed in one account.",
                List.of("Launch my company", "Pay myself a stable salary"), 0.7, List.of("diversification"), 4, 2);
        return new UserData(p,
                List.of(new SavingsPot("alex-emergency", SavingsCategory.EMERGENCY, "Personal buffer", 9600, 0)),
                List.of(new Holding("Global equity ETF", AssetClass.EQUITY_FUND, 18000), new Holding("Cash", AssetClass.CASH, 6000)),
                spending(Map.of(HOUSING, new double[]{1250, 1250}, GROCERIES, new double[]{400, 400}, TRANSPORT, new double[]{250, 260},
                        EATING_OUT, new double[]{360, 400}, SHOPPING, new double[]{300, 300}, SUBSCRIPTIONS, new double[]{120, 130},
                        OTHER, new double[]{500, 700})),
                List.of(new Project("launch", "Company launch reserve", "BUSINESS", 15000, 4000, YearMonth.now().plusMonths(10).atDay(1))));
    }

    static UserData maya() {
        UserProfile p = new UserProfile("maya", "Maya", 31, 4200, RiskTolerance.BALANCED,
                "I received an inheritance from my grandmother and I'm unsure how to invest it.",
                List.of("Buy a home in 2028"), 0.35, List.of(), 1, 0);
        return new UserData(p,
                List.of(new SavingsPot("maya-emergency", SavingsCategory.EMERGENCY, "Current savings", 5500, 0)),
                List.of(new Holding("Inherited cash", AssetClass.CASH, 220000), new Holding("Inherited ETF portfolio", AssetClass.EQUITY_FUND, 50000)),
                spending(Map.of(HOUSING, new double[]{1350, 1350}, GROCERIES, new double[]{350, 350}, TRANSPORT, new double[]{150, 150},
                        EATING_OUT, new double[]{450, 720}, SHOPPING, new double[]{380, 620}, TRAVEL, new double[]{300, 450},
                        SUBSCRIPTIONS, new double[]{140, 140})),
                List.of(new Project("home", "Home down payment", "HOME", 75000, 0, YearMonth.of(2028, 6).atDay(1))));
    }

    /** Max, 26, heir: the team demo's customer (same numbers as checkup-demo.html). */
    static UserData max() {
        UserProfile p = new UserProfile("max", "Max", 26, 3000, RiskTolerance.BALANCED,
                "I'm the heir of my family company: 82% of my wealth is in its shares. I sold everything in the crash test.",
                List.of("Build €1m of wealth by age 41", "Buy a flat in 4 years"), 0.45, List.of(), 0, 0);
        return new UserData(p,
                List.of(new SavingsPot("max-emergency", SavingsCategory.EMERGENCY, "Current savings", 3100, 0)),
                List.of(new Holding("Family company shares", AssetClass.SINGLE_STOCK, 401_800),
                        new Holding("Fund portfolio", AssetClass.EQUITY_FUND, 47_100)),   // + €38k flat savings = €490k total
                spending(Map.of(HOUSING, new double[]{1100, 1100}, GROCERIES, new double[]{380, 380}, TRANSPORT, new double[]{180, 180},
                        EATING_OUT, new double[]{380, 480}, SHOPPING, new double[]{330, 430}, TRAVEL, new double[]{150, 150},
                        SUBSCRIPTIONS, new double[]{200, 200})),
                List.of(new Project("flat", "Equity for a flat", "HOME", 135000, 38000, YearMonth.now().plusMonths(48).atDay(1))));
    }

    /** 6 months of transactions; each category moves linearly from start to end amount. */
    static List<Transaction> spending(Map<SpendingCategory, double[]> plan) {
        List<Transaction> out = new ArrayList<>();
        YearMonth first = YearMonth.now().minusMonths(6);
        for (int m = 0; m < 6; m++) {
            YearMonth ym = first.plusMonths(m);
            for (Map.Entry<SpendingCategory, double[]> e : plan.entrySet()) {
                double amount = e.getValue()[0] + (e.getValue()[1] - e.getValue()[0]) * m / 5.0;
                // split into two payments per month to look like real transactions
                out.add(new Transaction(ym.atDay(5), e.getKey(), Math.round(amount * 0.6), e.getKey().label));
                out.add(new Transaction(ym.atDay(20), e.getKey(), Math.round(amount * 0.4), e.getKey().label));
            }
        }
        return out;
    }
}
