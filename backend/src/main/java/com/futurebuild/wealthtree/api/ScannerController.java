package com.futurebuild.wealthtree.api;

import com.futurebuild.wealthtree.app.WealthTreeService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/** The team's Financial Health Scanner (CFPB well-being model), same output as score.py / score.js. */
@RestController
@RequestMapping("/api/users")
public class ScannerController {

    private final WealthTreeService service;

    public ScannerController(WealthTreeService service) {
        this.service = service;
    }

    /** The hardcoded questionnaire answers (CFPB PUF codes). */
    @GetMapping("/{id}/scanner/answers")
    public Map<String, Object> answers(@PathVariable String id) { return service.scannerAnswers(id); }

    /** Dimension scores, predicted CFPB score, age-band percentiles, habits, warnings. */
    @GetMapping("/{id}/scanner")
    public Map<String, Object> scan(@PathVariable String id) { return service.scan(id); }

    /** Body: the answers to change, e.g. {"SAVINGSRANGES": 5}. */
    @PostMapping("/{id}/scanner/what-if")
    public Map<String, Object> whatIf(@PathVariable String id, @RequestBody Map<String, Object> change) {
        return service.scanWhatIf(id, change);
    }
}
