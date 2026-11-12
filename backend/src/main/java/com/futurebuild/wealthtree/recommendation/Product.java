package com.futurebuild.wealthtree.recommendation;

/** A bank product an action links to. Names are placeholders: map them to real Deutsche Bank products. */
public record Product(String id, String name, String category, String url) {}
