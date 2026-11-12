package com.futurebuild.wealthtree.assessment;

import com.futurebuild.wealthtree.model.SpendingCategory;

import java.util.EnumMap;
import java.util.Map;

/**
 * Peer benchmark for spending: what German households in the same net-income class spend on average.
 *
 * Source: Statistisches Bundesamt (Destatis), Laufende Wirtschaftsrechnungen (LWR) 2024,
 * "Struktur der Konsumausgaben privater Haushalte nach dem monatlichen Haushaltsnettoeinkommen",
 * average per household and month in EUR (published 17 Aug 2026).
 * https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Einkommen-Konsum-Lebensbedingungen/Konsumausgaben-Lebenshaltungskosten/Tabellen/liste-monatlichen-haushalts-nettoeinkommen.html
 *
 * Mapping of our categories to the Destatis groups (approximate):
 *  HOUSING       = Wohnen, Energie, Wohnungsinstandhaltung
 *  GROCERIES     = Nahrungsmittel, Getränke, Tabakwaren
 *  TRANSPORT     = Verkehr
 *  EATING_OUT    = Gastronomie- und Beherbergungsdienstleistungen (includes hotel stays)
 *  SHOPPING      = Bekleidung und Schuhe + Innenausstattung, Haushaltsgeräte
 *  TRAVEL        = Freizeit, Sport und Kultur (includes package holidays and other leisure)
 *  SUBSCRIPTIONS = Information und Kommunikation
 *  OTHER         = Andere Waren und Dienstleistungen
 * The classes are household net income; households in higher classes are on average larger,
 * so for single people the benchmark is generous rather than strict.
 */
public final class SpendingBenchmarks {
    private SpendingBenchmarks() {}

    public static final String SOURCE = "Destatis, Laufende Wirtschaftsrechnungen 2024";

    /** Upper bounds of the net-income classes (EUR per month); the last class is open. */
    private static final double[] UPPER = {1300, 2600, 3600, 5000, Double.MAX_VALUE};
    private static final String[] LABEL = {"under €1,300", "€1,300–2,600", "€2,600–3,600", "€3,600–5,000", "€5,000 or more"};

    private static final Map<SpendingCategory, double[]> PEER = new EnumMap<>(SpendingCategory.class);

    static {
        //                                           <1,300  1,300–2,600  2,600–3,600  3,600–5,000  5,000+
        PEER.put(SpendingCategory.HOUSING,       new double[]{605, 816, 1064, 1271, 1666});
        PEER.put(SpendingCategory.GROCERIES,     new double[]{238, 306, 403, 502, 652});
        PEER.put(SpendingCategory.TRANSPORT,     new double[]{111, 204, 354, 468, 787});
        PEER.put(SpendingCategory.EATING_OUT,    new double[]{62, 102, 160, 226, 378});
        PEER.put(SpendingCategory.SHOPPING,      new double[]{40 + 46, 59 + 76, 95 + 120, 117 + 155, 188 + 249});
        PEER.put(SpendingCategory.TRAVEL,        new double[]{76, 147, 246, 309, 545});
        PEER.put(SpendingCategory.SUBSCRIPTIONS, new double[]{72, 104, 126, 148, 192});
        PEER.put(SpendingCategory.OTHER,         new double[]{41, 63, 93, 108, 169});
    }

    static int incomeClass(double netMonthlyIncome) {
        for (int i = 0; i < UPPER.length; i++) if (netMonthlyIncome < UPPER[i]) return i;
        return UPPER.length - 1;
    }

    /** Average monthly spending of households in the same net-income class. */
    public static double peerAverage(SpendingCategory c, double netMonthlyIncome) {
        return PEER.get(c)[incomeClass(netMonthlyIncome)];
    }

    /** e.g. "households with €3,600–5,000 net income (Destatis, Laufende Wirtschaftsrechnungen 2024)" */
    public static String peerGroup(double netMonthlyIncome) {
        return "households with " + LABEL[incomeClass(netMonthlyIncome)] + " net income (" + SOURCE + ")";
    }
}
