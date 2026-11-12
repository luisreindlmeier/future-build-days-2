package com.futurebuild.wealthtree.model;


import java.util.ArrayList;
import java.util.List;

/** Everything we know about one user: the input to the whole pipeline. */
public record UserData(
        UserProfile profile,
        List<SavingsPot> pots,
        List<Holding> holdings,
        List<Transaction> transactions,
        List<Project> projects
) implements java.io.Serializable {
    public UserData withProfile(UserProfile p) {
        return new UserData(p, pots, holdings, transactions, projects);
    }

    public UserData withProject(Project project) {
        List<Project> list = new ArrayList<>(projects);
        list.removeIf(x -> x.id().equals(project.id()));
        list.add(project);
        return new UserData(profile, pots, holdings, transactions, List.copyOf(list));
    }
}
