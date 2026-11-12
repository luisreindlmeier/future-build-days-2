package com.futurebuild.wealthtree.data;

import com.futurebuild.wealthtree.model.UserData;
import java.util.Collection;
import java.util.Optional;

public interface UserRepository {
    Collection<UserData> findAll();
    Optional<UserData> findById(String id);
    UserData save(UserData data);

    /** Back to the original demo data. */
    void reset();
}
