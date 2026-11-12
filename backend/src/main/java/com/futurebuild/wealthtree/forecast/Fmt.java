package com.futurebuild.wealthtree.forecast;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.NumberFormat;
import java.util.Locale;

/** Display strings exactly like the demo (eur, eurK, eurM, pct). */
public final class Fmt {
    private Fmt() {}

    public static String eur(double v) {
        return "€" + NumberFormat.getIntegerInstance(Locale.ENGLISH).format(Math.round(v));
    }

    public static String eurK(double v) {
        return v >= 1e4 ? "€" + Math.round(v / 1e3) + "k" : eur(v);
    }

    public static String eurM(double v) {
        if (Math.abs(v) >= 1e6) return "€" + new BigDecimal(v / 1e6).setScale(2, RoundingMode.HALF_UP).toPlainString() + "m";
        return eurK(v);
    }

    /** Round targets like "€1m", "€100k", "€10k" (goal labels). */
    public static String target(double v) {
        if (v >= 1e6 && v % 1e6 == 0) return "€" + (long) (v / 1e6) + "m";
        return eurM(v);
    }

    public static String pct(double v) {
        return Math.round(v * 100) + "%";
    }
}
