package com.futurebuild.wealthtree.kairos;

import com.futurebuild.wealthtree.app.WealthTreeService;
import com.futurebuild.wealthtree.assessment.Assessment;
import com.futurebuild.wealthtree.assessment.SpendingHabit;
import com.futurebuild.wealthtree.model.AssetClass;
import com.futurebuild.wealthtree.model.Holding;
import com.futurebuild.wealthtree.model.Project;
import com.futurebuild.wealthtree.model.SavingsCategory;
import com.futurebuild.wealthtree.model.SavingsPot;
import com.futurebuild.wealthtree.model.UserData;
import com.futurebuild.wealthtree.progress.ActionStatus;
import com.futurebuild.wealthtree.progress.ProgressSummary;
import com.futurebuild.wealthtree.progress.TrackedAction;
import com.futurebuild.wealthtree.recommendation.ActionType;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;

/**
 * Builds the team's customer intake (engine.EXAMPLE_CUSTOMER + "spending", see prediction-agent/engine.py)
 * from the customer's LIVE data: bank data, Destatis peer benchmarks and progress (verified actions).
 * So predictions and the action plan update when the tree grows.
 */
public class IntakeBuilder {

    private final WealthTreeService service;

    public IntakeBuilder(WealthTreeService service) {
        this.service = service;
    }

    public Map<String, Object> build(String id) {
        UserData d = service.user(id);
        Assessment a = service.assessment(id);
        KairosPersonas.Extras x = KairosPersonas.get(id).orElseThrow(() -> new NoSuchElementException("No Kairos profile for: " + id));
        ProgressSummary progress = service.progressSummary(id);
        List<TrackedAction> active = progress == null ? List.of()
                : progress.actions().stream().filter(TrackedAction::active).toList();

        double holdings = d.holdings().stream().mapToDouble(Holding::value).sum();
        double pots = d.pots().stream().mapToDouble(SavingsPot::balance).sum();
        double projects = d.projects().stream().mapToDouble(Project::savedAmount).sum();
        double wealth = holdings + pots + projects;
        double cash = d.pots().stream().filter(p -> p.category() == SavingsCategory.EMERGENCY || p.category() == SavingsCategory.GOALS)
                .mapToDouble(SavingsPot::balance).sum()
                + d.holdings().stream().filter(h -> h.assetClass() == AssetClass.CASH).mapToDouble(Holding::value).sum();   // project savings are earmarked, not buffer
        double company = d.holdings().stream().filter(h -> h.assetClass() == AssetClass.SINGLE_STOCK).mapToDouble(Holding::value).sum();

        // saving habit = base habit + committed standing orders / savings plans
        double saveCash = x.baseSavingCash(), saveInv = x.baseSavingInvested();
        for (TrackedAction t : active) {
            if (t.type() == ActionType.AUTO_SAVE) {
                if (SavingsCategory.RETIREMENT.name().equals(t.target())) saveInv += t.monthlyAmount();
                else saveCash += t.monthlyAmount();
            }
            if (t.type() == ActionType.INVEST_MONTHLY && !"rec-invest-idle".equals(t.recommendationId())) saveInv += t.monthlyAmount();
        }
        double income = d.profile().netMonthlyIncome(), spend = Math.round(a.monthlySpend());
        double room = Math.max(0, income - spend);
        if (saveCash + saveInv > room) {                         // can't save more than is left over
            double f = room / Math.max(1, saveCash + saveInv);
            saveCash = Math.round(saveCash * f);
            saveInv = Math.round(saveInv * f);
        }

        boolean verifiedBuffer = active.stream().anyMatch(t -> t.status() == ActionStatus.VERIFIED
                && SavingsCategory.EMERGENCY.name().equals(t.target()) && (t.type() == ActionType.AUTO_SAVE || t.type() == ActionType.MOVE_CASH));
        boolean diversifying = active.stream().anyMatch(t -> t.type() == ActionType.DIVERSIFY);
        boolean covered = d.pots().stream().anyMatch(p -> p.category() == SavingsCategory.PROTECTION);

        Map<String, Object> in = new LinkedHashMap<>();
        in.put("name", "Customer");                              // pseudonymous towards the AI gateway
        in.put("age", d.profile().age());
        in.put("profile", x.profile());
        in.put("purpose", x.purpose());
        in.put("wealth_total", Math.round(wealth));
        in.put("cash", Math.round(cash));
        in.put("company_share", wealth > 0 ? Math.round(company / wealth * 1000) / 1000.0 : 0.0);
        in.put("monthly_income", Math.round(income));
        if (x.incomeNote() != null) in.put("income_note", x.incomeNote());
        in.put("monthly_spending", Math.round(spend));
        in.put("monthly_saving_cash", Math.round(saveCash));
        in.put("monthly_saving_invested", Math.round(saveInv));
        in.put("crash_reaction", x.crashReaction());
        in.put("disability_cover", covered);
        in.put("will", x.will());
        in.put("has_buffer_plan", verifiedBuffer || a.bufferMonths() >= 3);
        in.put("has_diversification_plan", diversifying);
        if (x.bufferAmount() != null) in.put("buffer_amount", x.bufferAmount().intValue());
        if (x.investAmount() != null) in.put("invest_amount", x.investAmount().intValue());
        in.put("horizon_years", x.horizonYears());
        in.put("goals", x.goals());

        // spending intake for the action agent: wants vs Destatis peers, subscriptions, planned purchases
        List<Map<String, Object>> cats = new ArrayList<>();
        for (SpendingHabit h : a.habits()) {
            if (h.category().essential || h.category() == com.futurebuild.wealthtree.model.SpendingCategory.OTHER) continue;   // "other" is not a habit to cap
            Map<String, Object> c = new LinkedHashMap<>();
            c.put("id", h.category().name().toLowerCase());
            c.put("label", h.category().label);
            c.put("monthly", Math.round(h.monthlyAverage()));
            c.put("peer_median", Math.round(h.peerAverage()));      // Destatis average of the same income class
            cats.add(c);
        }
        List<Map<String, Object>> subs = x.subscriptions().stream()
                .map(s -> Map.<String, Object>of("name", s.name(), "monthly", s.monthly(), "last_used_days", s.lastUsedDays())).toList();
        List<Map<String, Object>> purchases = new ArrayList<>();
        x.plannedPurchases().forEach(p -> purchases.add(Map.of("label", p.label(), "amount", p.amount(), "in_months", p.inMonths())));
        // savings projects (home equity, trips…) are planned in the projects section, not sent as purchases to put on hold
        in.put("spending", Map.of("subscriptions", subs, "categories", cats, "planned_purchases", purchases));
        return in;
    }
}
