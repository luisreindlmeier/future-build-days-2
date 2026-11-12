package com.futurebuild.wealthtree.tree;

/** One branch per personal project. length = progress 0..1, fruit when fully funded. */
public record Branch(String projectId, String name, String type, double length, double angleDeg,
                     boolean fruit, boolean blossom, String detail) {}
