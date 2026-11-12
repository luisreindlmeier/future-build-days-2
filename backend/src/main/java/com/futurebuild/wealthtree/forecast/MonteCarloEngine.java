package com.futurebuild.wealthtree.forecast;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Seeded Monte Carlo, a 1:1 port of simulate() in the team's checkup-demo.html.
 * Same seed and same random draws for every scenario, so differences come from choices, not luck.
 * Three pots: single-company shares (co), invested money (dep), cash. Plus optional idle cash.
 */
public class MonteCarloEngine {

    private final Assumptions a;
    private final Map<String, SimResult> cache = new ConcurrentHashMap<>();

    public MonteCarloEngine(Assumptions a) {
        this.a = a;
    }

    public Assumptions assumptions() { return a; }

    public SimResult simulate(Finances f, World w, int years, List<ForecastGoal> goals) {
        String key = f + "|" + w + "|" + years + "|" + goals;
        return cache.computeIfAbsent(key, k -> run(f, w, years, goals));
    }

    private SimResult run(Finances f, World w, int Y, List<ForecastGoal> goals) {
        int N = a.paths();
        Mulberry32 r = new Mulberry32((int) a.seed());
        double[][] cols = new double[Y + 1][N];
        int shock = 0, panic = 0, gapEv = 0;
        double[] hits = new double[N];
        int nHits = 0;
        double start = f.total(), capCash = a.potCap() * f.spend();
        double gap = 12 * (f.spend() - (w.covered() ? a.coverRatio() * f.income() : 0));
        double mkDrift = a.mkMu() - a.mkSd() * a.mkSd() / 2, coDrift = a.coMu() - a.coSd() * a.coSd() / 2;
        double rhoC = Math.sqrt(1 - a.rho() * a.rho());

        for (int n = 0; n < N; n++) {
            double co = w.shareNow() * start, cash = f.cash(), idle = f.idle(), dep = start - co - cash - idle;
            boolean missed = false;
            int fS = 0, fP = 0, fG = 0;
            cols[0][n] = start;
            for (int y = 1; y <= Y; y++) {
                double u1 = Math.max(r.next(), 1e-12), u2 = r.next(), u3 = r.next();
                double m = Math.sqrt(-2 * Math.log(u1));
                double z1 = m * Math.cos(6.283185307 * u2), z2 = m * Math.sin(6.283185307 * u2);
                double rm = Math.exp(mkDrift + a.mkSd() * z1) - 1;
                double rc = Math.exp(coDrift + a.coSd() * (a.rho() * z1 + rhoC * z2)) - 1;
                boolean ill = u3 < a.pDis();
                if (y == 1 && w.deployIdle()) { dep += idle; idle = 0; }   // invested gradually during year 1
                double got = missed ? Math.min(rm, a.cashR()) : rm;          // a panic seller misses the rebound
                if (rc <= -0.4) {
                    if (fS == 0) hits[nHits++] = co * -rc / (co + dep + cash + idle);
                    fS = 1;
                }
                missed = w.panic() && rm < a.panicAt();
                if (missed) fP = 1;
                if (ill && !w.covered()) fG = 1;
                co *= 1 + rc;
                dep *= 1 + got;
                cash *= 1 + a.cashR();
                idle *= 1 + a.cashR();
                if (ill) cash -= gap;
                else { cash += w.saveCash() * 12; dep += w.saveInv() * 12; }
                if (cash > capCash) { dep += cash - capCash; cash = capCash; }   // buffer full: the rest is invested
                if (cash < 0) {
                    dep += cash; cash = 0;
                    if (dep < 0) { idle += dep; dep = 0; if (idle < 0) { co += idle; idle = 0; } }
                }
                if (w.glide()) {
                    double tot = co + dep + cash + idle, tg = Math.max(a.floor(), w.shareNow() - a.glide() * y);
                    if (co > tg * tot) { double x = co - tg * tot; co -= x; dep += x; }
                }
                cols[y][n] = co + dep + cash + idle;
            }
            shock += fS; panic += fP; gapEv += fG;
        }

        double[] p10 = new double[Y + 1], p50 = new double[Y + 1], p90 = new double[Y + 1];
        double[][] sorted = new double[Y + 1][];
        for (int y = 0; y <= Y; y++) {
            double[] s = cols[y].clone();
            Arrays.sort(s);
            sorted[y] = s;
            p10[y] = q(s, 0.1); p50[y] = q(s, 0.5); p90[y] = q(s, 0.9);
        }
        int below = 0;
        for (int n = 0; n < N; n++) if (cols[Y][n] < start) below++;
        Map<String, Double> goalSuccess = new LinkedHashMap<>();
        for (ForecastGoal g : goals) {
            int h = Math.min(Y, g.horizonYears());
            int ok = 0;
            for (int n = 0; n < N; n++) if (cols[h][n] >= g.target()) ok++;
            goalSuccess.put(g.id(), (double) ok / N);
        }
        double[] h = Arrays.copyOf(hits, nHits);
        Arrays.sort(h);
        return new SimResult(p10, p50, p90, (double) below / N, (double) shock / N, (double) panic / N,
                (double) gapEv / N, nHits > 0 ? h[nHits >> 1] : 0, goalSuccess);
    }

    private static double q(double[] s, double p) {
        return s[Math.min(s.length - 1, (int) Math.floor(p * s.length))];
    }

    /** mulberry32, bit-exact with the JavaScript version (32-bit int arithmetic). */
    static final class Mulberry32 {
        private int a;
        Mulberry32(int seed) { this.a = seed; }
        double next() {
            a = a + 0x6D2B79F5;
            int t = (a ^ (a >>> 15)) * (1 | a);
            t = (t + ((t ^ (t >>> 7)) * (61 | t))) ^ t;
            return Integer.toUnsignedLong(t ^ (t >>> 14)) / 4294967296.0;
        }
    }
}
