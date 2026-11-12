package com.futurebuild.wealthtree.api;

import com.futurebuild.wealthtree.app.WealthTreeService;
import com.futurebuild.wealthtree.assessment.Assessment;
import com.futurebuild.wealthtree.model.Project;
import com.futurebuild.wealthtree.model.UserData;
import com.futurebuild.wealthtree.projection.ProjectionResult;
import com.futurebuild.wealthtree.recommendation.Recommendation;
import com.futurebuild.wealthtree.tree.StormResult;
import com.futurebuild.wealthtree.tree.TreeState;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Comparator;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/users")
public class TreeController {

    private final WealthTreeService service;

    public TreeController(WealthTreeService service) {
        this.service = service;
    }

    /** Persona picker: lena, alex, maya. */
    @GetMapping
    public List<UserSummary> users() {
        return service.users().stream()
                .map(d -> {
                    TreeState t = service.tree(d.profile().id());
                    return new UserSummary(d.profile().id(), d.profile().name(), d.profile().age(), d.profile().situation(),
                            t.overallHealth(), t.status().name(), t.headline());
                })
                .sorted(Comparator.comparing(UserSummary::age))
                .toList();
    }

    /** Raw inputs (profile, pots, holdings, transactions, projects). */
    @GetMapping("/{id}")
    public UserData user(@PathVariable String id) { return service.user(id); }

    @GetMapping("/{id}/assessment")
    public Assessment assessment(@PathVariable String id) { return service.assessment(id); }

    /** Main endpoint for the frontend: everything needed to draw the tree. */
    @GetMapping("/{id}/tree")
    public TreeState tree(@PathVariable String id) { return service.tree(id); }

    @GetMapping("/{id}/recommendations")
    public List<Recommendation> recommendations(@PathVariable String id) { return service.recommendations(id); }

    /** Prediction: the tree after N months with the chosen actions (default: all, 12 months). */
    @PostMapping("/{id}/simulate")
    public ProjectionResult simulate(@PathVariable String id, @RequestBody(required = false) Requests.Simulate body) {
        List<String> ids = body == null ? null : body.actionIds();
        int months = body == null || body.months() == null ? 12 : body.months();
        return service.simulate(id, ids, months);
    }

    /** Storm test for the animation. */
    @PostMapping("/{id}/storm")
    public StormResult storm(@PathVariable String id) { return service.storm(id); }

    /** Update the non-deterministic inputs: age, risk, situation, goals. */
    @PutMapping("/{id}/context")
    public TreeState updateContext(@PathVariable String id, @RequestBody Requests.Context body) {
        service.updateContext(id, body.age(), body.riskTolerance(), body.situation(), body.goals());
        return service.tree(id);
    }

    /** Add or update a personal project (house, travel...). Returns the updated tree. */
    @PostMapping("/{id}/projects")
    public TreeState upsertProject(@PathVariable String id, @RequestBody Requests.ProjectInput p) {
        String pid = p.id() == null || p.id().isBlank() ? UUID.randomUUID().toString().substring(0, 8) : p.id();
        service.upsertProject(id, new Project(pid, p.name(), p.type(), p.targetAmount(), p.savedAmount(), p.targetDate()));
        return service.tree(id);
    }
}
