package com.futurebuild.wealthtree.progress;

import com.futurebuild.wealthtree.model.UserData;

import java.io.Serializable;
import java.util.Map;

/** Saves the users' data and progress so the tree remembers across restarts. */
public interface StateStore {
    record State(Map<String, UserData> users, Map<String, UserProgress> progress) implements Serializable {}

    State load();          // null if nothing saved yet
    void save(State s);
    void clear();
}
