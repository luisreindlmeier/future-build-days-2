package com.futurebuild.wealthtree.app;

import com.futurebuild.wealthtree.assessment.Assessment;
import com.futurebuild.wealthtree.assessment.Assessor;
import com.futurebuild.wealthtree.data.UserRepository;
import com.futurebuild.wealthtree.model.Project;
import com.futurebuild.wealthtree.model.RiskTolerance;
import com.futurebuild.wealthtree.model.UserData;
import com.futurebuild.wealthtree.projection.ProjectionResult;
import com.futurebuild.wealthtree.projection.ProjectionService;
import com.futurebuild.wealthtree.recommendation.Recommendation;
import com.futurebuild.wealthtree.recommendation.RecommendationEngine;
import com.futurebuild.wealthtree.scanner.FinancialHealthScanner;
import com.futurebuild.wealthtree.scanner.ScannerAnswers;
import com.futurebuild.wealthtree.scanner.WellBeing;
import com.futurebuild.wealthtree.tree.StormResult;
import com.futurebuild.wealthtree.tree.TreeBuilder;
import com.futurebuild.wealthtree.tree.TreeState;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;

/** Facade over the pipeline: inputs -> assessment -> recommendations/prediction -> tree. Framework-free. */
public class WealthTreeService {

    private final UserRepository repo;
    private final Assessor assessor;
    private final RecommendationEngine engine;
    private final TreeBuilder treeBuilder;
    private final ProjectionService projection;
    private final FinancialHealthScanner scanner;
    private java.util.function.Function<String, Map<String, Object>> answersProvider =
            id -> ScannerAnswers.get(id).orElse(null);
    private java.util.function.Function<String, com.futurebuild.wealthtree.progress.ProgressSummary> progressProvider = id -> null;

    /** Current questionnaire answers (the progress service keeps them up to date). */
    public void setAnswersProvider(java.util.function.Function<String, Map<String, Object>> f) { this.answersProvider = f; }

    /** Remembered growth for the tree (trend, events, milestones). */
    public void setProgressProvider(java.util.function.Function<String, com.futurebuild.wealthtree.progress.ProgressSummary> f) { this.progressProvider = f; }

    private Map<String, Object> answers(String id) { return answersProvider.apply(id); }

    /** Remembered progress (null when progress tracking is not configured). */
    public com.futurebuild.wealthtree.progress.ProgressSummary progressSummary(String id) { return progressProvider.apply(id); }

    /** Actions that are done once verified; ongoing ones (saving, investing, limits) stay visible. */
    private static final java.util.Set<com.futurebuild.wealthtree.recommendation.ActionType> ONE_OFF = java.util.EnumSet.of(
            com.futurebuild.wealthtree.recommendation.ActionType.ADVISOR_MEETING,
            com.futurebuild.wealthtree.recommendation.ActionType.PROTECT,
            com.futurebuild.wealthtree.recommendation.ActionType.SEPARATE_ACCOUNTS,
            com.futurebuild.wealthtree.recommendation.ActionType.MOVE_CASH);

    public WealthTreeService(UserRepository repo, Assessor assessor, RecommendationEngine engine,
                             TreeBuilder treeBuilder, ProjectionService projection) {
        this(repo, assessor, engine, treeBuilder, projection, null);
    }

    /** With a scanner, the tree, recommendations and predictions use the CFPB well-being model. */
    public WealthTreeService(UserRepository repo, Assessor assessor, RecommendationEngine engine,
                             TreeBuilder treeBuilder, ProjectionService projection, FinancialHealthScanner scanner) {
        this.repo = repo;
        this.assessor = assessor;
        this.engine = engine;
        this.treeBuilder = treeBuilder;
        this.projection = projection;
        this.scanner = scanner;
        if (scanner != null) projection.setWellbeing(this::wellbeingAfter);
    }

    // ---------------------------------------------------------------- scanner (CFPB well-being model)
    public Map<String, Object> scannerAnswers(String id) {
        user(id);
        Map<String, Object> a = answers(id);
        if (a == null || a.isEmpty()) throw new NoSuchElementException("No questionnaire answers for: " + id);
        return a;
    }

    /** Full scanner output, same format as the team's score.py / score.js. */
    public Map<String, Object> scan(String id) {
        requireScanner();
        return scanner.score(scannerAnswers(id));
    }

    /** What-if on the questionnaire: change some answers, everything else fixed. */
    public Map<String, Object> scanWhatIf(String id, Map<String, Object> change) {
        requireScanner();
        return scanner.whatIf(scannerAnswers(id), change);
    }

    private WellBeing wellbeing(String id) {
        if (scanner == null) return null;
        Map<String, Object> a = answers(id);
        return a == null || a.isEmpty() ? null : WellBeing.of(scanner.score(a));
    }

    private WellBeing wellbeingAfter(String id, List<Recommendation> done) {
        Map<String, Object> a = answers(id);
        return a == null || a.isEmpty() ? null : WellBeing.of(scanner.score(ScannerAnswers.applyAll(a, done)));
    }

    private void requireScanner() {
        if (scanner == null) throw new IllegalStateException("Scanner not configured");
    }

    public Collection<UserData> users() { return repo.findAll(); }

    public UserData user(String id) {
        return repo.findById(id).orElseThrow(() -> new NoSuchElementException("Unknown user: " + id));
    }

    public Assessment assessment(String id) { return assessor.assess(user(id)); }

    public TreeState tree(String id) {
        UserData d = user(id);
        return treeBuilder.build(d, assessor.assess(d), wellbeing(id)).withProgress(progressProvider.apply(id));
    }

    /** Recommendations, each with its predicted gain on the CFPB scale where the questionnaire can measure it. */
    @SuppressWarnings("unchecked")
    public List<Recommendation> recommendations(String id) {
        UserData d = user(id);
        List<Recommendation> recs = engine.recommend(d, assessor.assess(d));
        // one-off actions that are already verified are done: don't recommend them again
        var progress = progressProvider.apply(id);
        if (progress != null) {
            var done = progress.actions().stream()
                    .filter(t -> t.status() == com.futurebuild.wealthtree.progress.ActionStatus.VERIFIED && ONE_OFF.contains(t.type()))
                    .map(t -> t.actionId()).collect(java.util.stream.Collectors.toSet());
            recs = recs.stream().filter(r -> !done.contains(r.action().id())).toList();
        }
        Map<String, Object> answers = scanner == null ? null : answers(id);
        if (answers == null || answers.isEmpty()) return recs;
        return recs.stream().map(r -> {
            Map<String, Object> change = ScannerAnswers.changeFor(r, answers);
            if (change.isEmpty()) return r;
            Object g = scanner.whatIf(answers, change).get("predicted_gain");
            // no measurable effect (e.g. habits are display-only, or the answer is already at the top) -> null
            return g == null || Math.abs((Double) g) < 0.05 ? r : r.withWellbeingGain(Math.round((Double) g * 10) / 10.0);
        }).toList();
    }

    /** actionIds empty = "do nothing" baseline; null = apply all recommendations. */
    public ProjectionResult simulate(String id, List<String> actionIds, int months) {
        UserData d = user(id);
        List<Recommendation> all = recommendations(id);
        List<Recommendation> chosen = actionIds == null ? all
                : all.stream().filter(r -> actionIds.contains(r.action().id()) || actionIds.contains(r.id())).toList();
        return projection.project(d, chosen, Math.max(1, Math.min(months, 120)));
    }

    public StormResult storm(String id) {
        UserData d = user(id);
        return treeBuilder.storm(d, assessor.assess(d));
    }

    public UserData updateContext(String id, Integer age, RiskTolerance risk, String situation, List<String> goals) {
        UserData d = user(id);
        var p = d.profile();
        return repo.save(d.withProfile(p.withContext(
                age != null ? age : p.age(),
                risk != null ? risk : p.riskTolerance(),
                situation != null ? situation : p.situation(),
                goals != null ? goals : p.goals())));
    }

    public UserData upsertProject(String id, Project project) {
        return repo.save(user(id).withProject(project));
    }
}
