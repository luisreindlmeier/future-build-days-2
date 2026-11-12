package com.futurebuild.wealthtree.progress;

import com.futurebuild.wealthtree.recommendation.ActionType;

import java.io.Serializable;
import java.time.YearMonth;

/** A committed action and its proof. stepsDone counts monthly steps (e.g. 12 investment steps). */
public record TrackedAction(
        String actionId, String recommendationId, String title, ActionType type, String target,
        double monthlyAmount, double oneOffAmount, String trainingId,
        ActionStatus status, YearMonth committedIn, YearMonth verifiedIn, String evidence, int stepsDone
) implements Serializable {

    public TrackedAction verified(YearMonth m, String why) {
        return new TrackedAction(actionId, recommendationId, title, type, target, monthlyAmount, oneOffAmount, trainingId,
                ActionStatus.VERIFIED, committedIn, m, why, stepsDone);
    }

    public TrackedAction withStatus(ActionStatus s) {
        return new TrackedAction(actionId, recommendationId, title, type, target, monthlyAmount, oneOffAmount, trainingId,
                s, committedIn, verifiedIn, evidence, stepsDone);
    }

    public TrackedAction step() {
        return new TrackedAction(actionId, recommendationId, title, type, target, monthlyAmount, oneOffAmount, trainingId,
                status, committedIn, verifiedIn, evidence, stepsDone + 1);
    }

    public boolean active() { return status != ActionStatus.DROPPED && status != ActionStatus.REPLACED; }
}
