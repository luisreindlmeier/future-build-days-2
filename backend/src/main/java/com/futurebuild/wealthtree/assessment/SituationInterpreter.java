package com.futurebuild.wealthtree.assessment;

import com.futurebuild.wealthtree.model.UserProfile;

/**
 * Turns the user's own words into structured context.
 * Default: keyword rules. Swap in an LLM-backed implementation later; keep the same output.
 */
public interface SituationInterpreter {
    SituationContext interpret(UserProfile profile);
}
