package com.futurebuild.wealthtree.projection;

import com.futurebuild.wealthtree.assessment.Assessment;
import com.futurebuild.wealthtree.tree.TreeState;
import java.util.List;

/** Prediction: what the tree looks like after N months if the chosen actions are followed. */
public record ProjectionResult(int months, List<String> appliedActionIds, int scoreBefore, int scoreAfter,
                               Assessment assessmentAfter, TreeState treeAfter, List<TimelinePoint> timeline) {}
