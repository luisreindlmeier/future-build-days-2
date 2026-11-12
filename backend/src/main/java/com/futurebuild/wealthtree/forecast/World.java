package com.futurebuild.wealthtree.forecast;

/** One description of the customer's habits for one scenario (the demo's world()). */
public record World(
        double shareNow,     // share of wealth in one company today
        boolean glide,       // diversify step by step (family-table plan)
        double saveCash,     // monthly saving into cash
        double saveInv,      // monthly saving into investments
        boolean covered,     // disability cover in place
        boolean panic,       // sells in a market fall (from the crash test)
        boolean deployIdle   // idle cash gets invested (engine extension)
) {
    public World withSaveCash(double v) { return new World(shareNow, glide, v, saveInv, covered, panic, deployIdle); }
    public World withSaveInv(double v) { return new World(shareNow, glide, saveCash, v, covered, panic, deployIdle); }
    public World withGlide() { return new World(shareNow, true, saveCash, saveInv, covered, panic, deployIdle); }
    public World withCover() { return new World(shareNow, glide, saveCash, saveInv, true, panic, deployIdle); }
    public World holding() { return new World(shareNow, glide, saveCash, saveInv, covered, false, deployIdle); }
    public World deployingIdle() { return new World(shareNow, glide, saveCash, saveInv, covered, panic, true); }
}
