/* =====================================================================
   ENGINE — deterministic rules. Same inputs always give the same verdict.
   The AI layer (ai.js) phrases and reasons on top; it never replaces this.
   ===================================================================== */

/* ---------- small helpers ---------- */
const eur = v => "€" + Math.round(v).toLocaleString("en-US");
const MO = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
const ym = m => { const a = CFG.startYM + m; return MO[a % 12] + " " + Math.floor(a / 12); };
const yOf = m => Math.floor((CFG.startYM + m) / 12);
const word = v => v >= 75 ? "Excellent" : v >= 55 ? "Strong" : v >= 40 ? "Building" : "Needs care";
const annuity = (amount, yearlyRate, months) => {
  const r = yearlyRate / 12;
  return amount * r / (1 - Math.pow(1 + r, -months));
};
const worst = (a, b) => ["good", "warn", "bad"].indexOf(a) >= ["good", "warn", "bad"].indexOf(b) ? a : b;

const foundationBlocked = user => user.vitals.Foundation < CFG.caps.foundationGate;

/* ---------- what can this customer afford? ----------
   Computed from the customer's real numbers, NOT by the AI. The AI gets
   these as hard limits and fixPlan() enforces them on its answer, so a
   €1,000 salary can never be told to buy a €60,000 car on credit. */
const maxLoanFor = (payment, yearlyRate, months) => {
  if (payment <= 0) return 0;
  const r = yearlyRate / 12;
  return r ? payment * (1 - Math.pow(1 + r, -months)) / r : payment * months;
};

function affordability(user, p) {
  const T = PROJECT_TYPES[p.type];
  const bufferKept = 3 * user.costs;                         // emergency money is never spent on a project
  const freeCash = Math.max(0, user.savings - bufferKept);
  const monthlyFree = user.income - user.costs;              // what is left each month today
  const months = Math.max(0, p.targetM ?? 0);
  const savedByTarget = Math.round(freeCash + Math.max(0, user.capacity) * months);

  let payCap = 0, rate = 0, term = 0, why = "";
  if (T.noLoan) why = "Kairos never lends for this kind of plan.";
  else if (foundationBlocked(user)) why = `Foundation vital ${user.vitals.Foundation}/100 is under ${CFG.caps.foundationGate}: no loan until the base is rebuilt.`;
  else if (p.type === "car") {
    // rule: loan + running costs <= 15% of income, AND it must fit in the money left each month
    payCap = Math.min(user.income * CFG.caps.carPct, monthlyFree) - CFG.rates.carRunning;
    rate = CFG.rates.carLoan; term = CFG.rates.carMonths;
    if (payCap <= 0) why = `With ${eur(user.income)} income and ${eur(monthlyFree)} left each month, there is no room for a car payment plus ~${eur(CFG.rates.carRunning)} running costs.`;
  } else if (p.type === "home") {
    payCap = user.income * CFG.caps.homePct;                 // mortgage replaces rent, so no monthlyFree cap
    rate = CFG.rates.mortgage; term = 360;
  } else if (p.type === "studies") {
    payCap = Math.min(user.income * 0.10, monthlyFree);
    rate = CFG.rates.studiesLoan; term = 120;
    if (payCap <= 0) why = "No room in the monthly budget for a student-loan payment.";
  } else if (p.type === "business") {
    rate = CFG.rates.bizLoan; term = 96;                     // capped later by the business's own profit
  }
  payCap = Math.max(0, Math.round(payCap));
  let maxLoan = p.type === "business" && !why ? 125000       // KfW StartGeld ceiling; profit check in fixPlan
              : Math.round(maxLoanFor(payCap, rate, term));
  // car: the loan covers at most 80% of the price, so it can be at most 4x the own money
  if (p.type === "car") maxLoan = Math.round(Math.min(maxLoan, savedByTarget * CFG.rates.carFinanceShare / (1 - CFG.rates.carFinanceShare)));

  const extra = p.type === "home" ? 1 + CFG.rates.purchaseCosts : 1;   // home: price + 12% buying costs
  const maxPriceByTarget = Math.round((savedByTarget + maxLoan) / extra);
  // the user writes the date in the description, so give the AI the limit for several horizons
  const priceIn = m => Math.round((freeCash + Math.max(0, user.capacity) * m + maxLoan) / extra);
  return {
    income: user.income, monthly_costs: user.costs, monthly_free: monthlyFree,
    saving_capacity: user.capacity, cash: user.savings, emergency_buffer_kept: bufferKept,
    free_cash_now: freeCash, saved_by_target: savedByTarget, target_date: ym(months),
    loan_allowed: maxLoan > 0, loan_block_reason: maxLoan > 0 ? "" : why,
    max_loan_payment: p.type === "business" ? null : payCap,
    max_loan: maxLoan, loan_rate: rate, loan_term_months: term,
    max_price_by_target: maxPriceByTarget,
    max_price_if_ready_in: { now: priceIn(0), "6 months": priceIn(6), "12 months": priceIn(12),
                             "24 months": priceIn(24), "36 months": priceIn(36), "60 months": priceIn(60) }
  };
}

/* ---------- how much money a project needs up front ---------- */
function goalAmount(user, p) {
  if (p.plan) return p.plan.own;                   // the AI plan knows the real cost (own share, after any loan)
  if (p.type === "car")
    return (p.finance && !foundationBlocked(user)) ? p.budget * (1 - CFG.rates.carFinanceShare) : p.budget;
  if (p.type === "home") {
    const price = p.sqm * CFG.cities[p.city][1];
    return price * (0.20 + CFG.rates.purchaseCosts); // 20% down + purchase costs
  }
  return p.cost; // trip, business, family, studies, sabbatical
}

/* ---------- savings waterfall ----------
   Cushion fills first (30% of capacity until 3 months of costs),
   then projects are funded nearest target date first. */
function simulate(user, projects) {
  const cushionTarget = 3 * user.costs;
  let cushion = Math.min(user.savings, cushionTarget);
  let free = user.savings - cushion;

  const goals = projects
    .map(p => ({ p, need: goalAmount(user, p), ready: null }))
    .sort((a, b) => a.p.targetM - b.p.targetM);

  for (const g of goals) {           // existing free savings
    const put = Math.min(free, g.need);
    g.need -= put; free -= put;
    if (g.need <= 0) g.ready = 0;
  }
  for (let m = 1; m <= 180; m++) {   // month by month
    let cap = user.capacity;
    if (cushion < cushionTarget) {
      const c = Math.min(cap * CFG.caps.cushionShare, cushionTarget - cushion);
      cushion += c; cap -= c;
    }
    for (const g of goals) {
      if (g.ready !== null) continue;
      const put = Math.min(cap, g.need);
      g.need -= put; cap -= put;
      if (g.need <= 0) g.ready = m;
      if (cap <= 0) break;
    }
  }
  const map = new Map(goals.map(g => [g.p, g.ready]));
  return { ready: p => map.get(p), cushion, cushionTarget };
}

/* ---------- the verdict ----------
   Returns { v: good|warn|bad, R: [[kind,text]], how, db, fitM, pmt } */
function judge(user, p, sim) {
  const T = PROJECT_TYPES[p.type];
  const ready = sim.ready(p);
  const readyTxt = ready === null ? "after 2041" : ym(ready);
  const onTime = ready !== null && ready <= p.targetM;

  if (p.type === "car") return judgeCar(user, p, sim, readyTxt, onTime, T);
  if (p.type === "home") return judgeHome(user, p, sim, readyTxt, T);

  /* generic savings goals: trip, business, family, studies, sabbatical */
  const R = [];
  let v = onTime ? "good" : "warn";

  if (p.type === "trip") {
    const x = p.cost / user.income;
    const lv = x <= CFG.caps.tripGoodX ? "good" : x <= CFG.caps.tripAdjustX ? "warn" : "bad";
    v = worst(v, lv);
    R.push([lv === "good" ? "ok" : lv, `The trip costs ${x.toFixed(1)}× your monthly income. Fine if it's saved for, never borrowed.`]);
  }
  if (p.type === "business") {
    const runway = user.savings / user.costs;
    const ok = runway >= CFG.caps.bizRunwayMonths;
    if (!ok) v = worst(v, "warn");
    R.push([ok ? "ok" : "warn", `Personal runway: ${runway.toFixed(1)} months of living costs saved — founders need ${CFG.caps.bizRunwayMonths}.`]);
    R.push(["ok", "Keep business and personal money in separate accounts from day one."]);
  }
  R.push([onTime ? "ok" : "warn",
    onTime ? `Your ${eur(p.cost)} is ready around ${readyTxt} — on time.`
           : `Ready around ${readyTxt}, after your target ${ym(p.targetM)} — move the date or trim the cost.`]);
  if (T.noLoan) R.push(["rule", "Kairos never finances consumption: no loan for this, whatever the score."]);

  return {
    v, R,
    how: `<b>${onTime ? "On track." : "Tight."}</b> Savings flow nearest-date-first: ready around <b>${readyTxt}</b> vs. target ${ym(p.targetM)}.`,
    db: T.db, fitM: onTime ? ready : p.targetM
  };
}

function judgeCar(user, p, sim, readyTxt, onTime, T) {
  if (p.finance && foundationBlocked(user)) {
    return {
      v: "bad",
      R: [
        ["bad", `Foundation is "${word(user.vitals.Foundation)}" (${user.vitals.Foundation}/100): no financing until it's rebuilt.`],
        ["warn", `Unlock it: 1 month of cushion (${eur(user.costs)}) and no expensive debt.`],
        ["ok", `Save-up path stays open: ${eur(p.budget)} ready around ${readyTxt}.`]
      ],
      how: `<b>Foundation first.</b> Kairos never recommends a loan on a fragile base.`,
      db: "A savings pot with a standing order — financing talk comes later.", fitM: null
    };
  }
  if (!p.finance) {
    return {
      v: onTime ? "good" : "warn",
      R: [
        ["ok", `No loan, no interest — the car costs exactly ${eur(p.budget)}.`],
        [onTime ? "ok" : "warn", onTime ? `Ready around ${readyTxt}, before your target.` : `Ready around ${readyTxt} — after your target ${ym(p.targetM)}.`]
      ],
      how: `<b>${onTime ? "On track." : "Tight."}</b> Full price saved by <b>${readyTxt}</b>.`,
      db: "Savings pot + maxblue ETF plan if the date is 3+ years away.", fitM: sim.ready(p)
    };
  }
  const loan = p.budget * CFG.rates.carFinanceShare;
  const pmt = annuity(loan, CFG.rates.carLoan, CFG.rates.carMonths);
  const tot = pmt + CFG.rates.carRunning;
  const pct = tot / user.income;
  const interest = pmt * CFG.rates.carMonths - loan;
  const capPmt = user.income * CFG.caps.carPct - CFG.rates.carRunning;
  const maxPrice = capPmt > 0
    ? (capPmt / (CFG.rates.carLoan / 12) * (1 - Math.pow(1 + CFG.rates.carLoan / 12, -CFG.rates.carMonths))) / CFG.rates.carFinanceShare
    : 0;
  const v = pct <= CFG.caps.carPct ? "good" : pct <= CFG.caps.carPctAdjust ? "warn" : "bad";

  const R = [
    [v === "good" ? "ok" : v, `${eur(tot)} a month (${eur(pmt)} loan + ${eur(CFG.rates.carRunning)} running) = <b>${Math.round(pct * 100)}% of income</b>. Cap for mobility: ${CFG.caps.carPct * 100}%.`],
    [interest > 1200 ? "warn" : "ok", `Total interest over ${CFG.rates.carMonths / 12} years: about ${eur(interest)}.`],
    ["ok", `Fits the rule at about <b>${eur(maxPrice)}</b> — or save longer and borrow less.`]
  ];
  if (p.budget < CFG.market.evAvg * 0.6)
    R.push(["warn", `Budget is ${Math.round(p.budget / CFG.market.evAvg * 100)}% of the EV market average (${eur(CFG.market.evAvg)}) — expect compromises.`]);

  let fitM = null; // mandate moment: first year the payment fits as income grows
  for (let t = 0; t <= 15; t++) {
    if (tot <= user.income * Math.pow(1 + CFG.rates.incomeGrowth, t) * CFG.caps.carPct) { fitM = t * 12; break; }
  }
  return {
    v, R,
    how: `<b>${v === "good" ? "Fits." : v === "warn" ? "Over the limit." : "Too heavy."}</b> Down payment ${eur(p.budget * (1 - CFG.rates.carFinanceShare))} is ready around <b>${readyTxt}</b>.`,
    db: T.db, fitM, pmt
  };
}

function judgeHome(user, p, sim, readyTxt, T) {
  const price = p.sqm * CFG.cities[p.city][1];
  const equity = Math.max(0, user.savings - 3 * user.costs);
  const loan = Math.max(0, price * (1 + CFG.rates.purchaseCosts) - equity);
  const pmt = loan * (CFG.rates.mortgage + CFG.rates.mortgageRepay) / 12;
  const pct = pmt / user.income;
  const v0 = pct <= CFG.caps.homePct ? "good" : pct <= CFG.caps.homePctAdjust ? "warn" : "bad";

  const R = [[v0 === "good" ? "ok" : v0,
    `${CFG.cities[p.city][0]}, ${p.sqm} m² ≈ ${eur(price)} → with ${CFG.rates.purchaseCosts * 100}% costs and ${eur(equity)} equity, the mortgage is <b>${eur(pmt)} a month = ${Math.round(pct * 100)}% of income</b>. Cap: ${CFG.caps.homePct * 100}%.`]];

  const budget = user.income * CFG.caps.homePct; // most expensive city that fits today
  let fitCity = null;
  for (const [name, sqmP] of CFG.cities) {
    const ln = Math.max(0, p.sqm * sqmP * (1 + CFG.rates.purchaseCosts) - equity);
    if (ln * (CFG.rates.mortgage + CFG.rates.mortgageRepay) / 12 <= budget) { fitCity = name; break; }
  }
  if (v0 !== "good")
    R.push(["ok", fitCity ? `The same ${p.sqm} m² fits today in <b>${fitCity}</b>.` : "No listed city fits yet — equity first."]);

  let fitM = null; // mandate moment: equity +€500/mo, income +3%/yr
  for (let t = 0; t <= 15; t++) {
    const ln2 = Math.max(0, price * (1 + CFG.rates.purchaseCosts) - (equity + 500 * 12 * t));
    if (ln2 * (CFG.rates.mortgage + CFG.rates.mortgageRepay) / 12 <= user.income * Math.pow(1 + CFG.rates.incomeGrowth, t) * CFG.caps.homePct) { fitM = t * 12; break; }
  }
  if (v0 !== "good")
    R.push([fitM !== null ? "warn" : "bad", fitM !== null ? `${CFG.cities[p.city][0]} path: keep building equity and it turns green around <b>${yOf(fitM)}</b>.` : "Out of reach on this income — adjust city or size."]);
  if (foundationBlocked(user))
    R.unshift(["bad", `Foundation "${word(user.vitals.Foundation)}": no mortgage talk before the base is rebuilt.`]);

  return {
    v: foundationBlocked(user) ? "bad" : v0, R,
    how: `<b>${v0 === "good" ? "Fits." : v0 === "warn" ? "Close." : "Not yet."}</b> Down payment ready around <b>${readyTxt}</b>.`,
    db: T.db, fitM, pmt: v0 === "good" ? pmt : null
  };
}
