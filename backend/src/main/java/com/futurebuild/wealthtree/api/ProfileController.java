package com.futurebuild.wealthtree.api;

import com.futurebuild.wealthtree.profiles.ProfileRequest;
import com.futurebuild.wealthtree.profiles.ProfileService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Customer-made profiles. Create one from the onboarding form, read the form back to personalise it,
 * save changes (the agents re-run), or delete it. Demo customers can be read as a form (to copy them)
 * but not changed.
 */
@RestController
@RequestMapping("/api/profiles")
public class ProfileController {
    private final ProfileService profiles;

    public ProfileController(ProfileService profiles) {
        this.profiles = profiles;
    }

    @GetMapping
    public List<ProfileService.Summary> list() { return profiles.list(); }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ProfileService.Summary create(@RequestBody ProfileRequest request) { return profiles.create(request); }

    @GetMapping("/{id}")
    public ProfileRequest form(@PathVariable String id) { return profiles.form(id); }

    @PutMapping("/{id}")
    public ProfileService.Summary update(@PathVariable String id, @RequestBody ProfileRequest request) {
        return profiles.update(id, request);
    }

    @DeleteMapping("/{id}")
    public Map<String, Object> delete(@PathVariable String id) {
        profiles.delete(id);
        return Map.of("deleted", id);
    }
}
