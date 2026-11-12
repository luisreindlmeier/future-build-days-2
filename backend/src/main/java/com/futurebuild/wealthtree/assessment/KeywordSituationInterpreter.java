package com.futurebuild.wealthtree.assessment;

import com.futurebuild.wealthtree.model.UserProfile;
import java.util.EnumSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public class KeywordSituationInterpreter implements SituationInterpreter {

    private static final Map<SituationFlag, List<String>> KEYWORDS = Map.of(
            SituationFlag.FIRST_SALARY, List.of("first salary", "first job", "graduated", "erstes gehalt"),
            SituationFlag.VARIABLE_INCOME, List.of("variable income", "freelance", "self-employed", "irregular income"),
            SituationFlag.STARTING_BUSINESS, List.of("start a business", "starting a business", "startup", "start-up", "founder", "my company"),
            SituationFlag.INHERITANCE, List.of("inherit", "inheritance", "erbe"),
            SituationFlag.FAMILY_BUSINESS, List.of("family business", "family company", "succession", "take over"),
            SituationFlag.BUYING_HOME, List.of("house", "home", "flat", "apartment", "wohnung"),
            SituationFlag.STUDIES, List.of("master", "mba", "study", "degree"),
            SituationFlag.NEW_FAMILY, List.of("baby", "child", "married", "wedding")
    );

    @Override
    public SituationContext interpret(UserProfile p) {
        String text = ((p.situation() == null ? "" : p.situation()) + " " + String.join(" ", p.goals()))
                .toLowerCase(Locale.ROOT);
        Set<SituationFlag> flags = EnumSet.noneOf(SituationFlag.class);
        KEYWORDS.forEach((flag, words) -> {
            if (words.stream().anyMatch(text::contains)) flags.add(flag);
        });
        return new SituationContext(LifeStage.ofAge(p.age()), p.riskTolerance(), flags, p.goals());
    }
}
