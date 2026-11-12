package com.futurebuild.wealthtree.tree;

public record Weather(Type type, String reason) {
    public enum Type { CALM, BREEZY, WINDY, STORM }
}
