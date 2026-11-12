/* =====================================================================
   CUSTOMER — loads the real customer assessment (the JSON the scan /
   prediction / action agents produce) and turns it into the `user`
   object the app and the AI think from.

   Source: CUSTOMER_FILE. Two formats are accepted:
   1. a simple test case (test-worst-case.json):
        { "name", "age", "monthly_income", "monthly_spending", "savings",
          "inheritance": { "received": true|false, "amount": EUR } }
   2. the full assessment (input.txt) — text around the JSON is fine.
   Pick another file without editing code: index.html?customer=input.txt
   If the file can't be read (page opened as file://, file missing),
   the app keeps the demo constant SCAN from config.js.
   ===================================================================== */

const CUSTOMER_FILE = new URLSearchParams(location.search).get("customer") || "test-worst-case.json";

/* Pull the JSON object out of the file text. */
function parseAssessment(text) {
  const fenced = text.match(/```json\s*([\s\S]*?)```/);
  const raw = fenced ? fenced[1] : text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
  return JSON.parse(raw);
}

const clamp100 = v => Math.max(0, Math.min(100, Math.round(v)));

/* The assessment has no 0-100 vitals, so we derive them from the raw
   intake. Simple, explainable formulas — tune them here. */
function deriveVitals(x) {
  const bufferMonths = x.cash / Math.max(1, x.monthly_spending);
  const saveRate = ((x.monthly_saving_cash || 0) + (x.monthly_saving_invested || 0)) / Math.max(1, x.monthly_income);
  const unusedSubs = ((x.spending || {}).subscriptions || []).filter(s => s.last_used_days > 60).length;
  const overspend = ((x.spending || {}).categories || []).filter(c => c.monthly > 1.5 * c.peer_median).length;
  const crash = { sell: 20, hold: 60, buy: 80 }[x.crash_reaction] ?? 50;
  return {
    // emergency cash (6 months = full marks) + protections in place
    Foundation: clamp100(bufferMonths / 6 * 60 + (x.disability_cover ? 20 : 0) + (x.will ? 10 : 0) + (x.has_buffer_plan ? 10 : 0)),
    // saving rate (20% of income = full marks), minus waste
    Habits: clamp100(saveRate / 0.20 * 100 - unusedSubs * 8 - overspend * 10),
    // how they behave in a market crash (selling = poor understanding of risk)
    Knowledge: clamp100(crash + (x.monthly_saving_invested > 0 ? 15 : 0)),
    // spread of wealth (all in one company = poor) + a plan for it
    Future: clamp100((1 - (x.company_share || 0)) * 100 + (x.has_diversification_plan ? 25 : 0) + (x.monthly_saving_invested > 0 ? 10 : 0)),
    // stress signal: panic selling and a thin buffer
    Calm: clamp100(crash + Math.min(bufferMonths, 6) / 6 * 40)
  };
}

function levelOf(vitals) {
  const avg = Object.values(vitals).reduce((s, v) => s + v, 0) / 5;
  return avg < 30 ? "Seed" : avg < 45 ? "Sprout" : avg < 60 ? "Rooted" : avg < 75 ? "Thriving" : "Flourishing";
}

/* Simple test case → the app's `user`.
   An inheritance already RECEIVED counts as cash; one only expected does
   not (the bank never plans with money the customer doesn't have yet). */
function simpleToUser(c) {
  const inh = c.inheritance || {};
  const inherited = inh.received ? Math.max(0, +inh.amount || 0) : 0;
  const income = +c.monthly_income || 0;
  const costs = +c.monthly_spending || Math.round(income * 0.9);
  const cash = (+c.savings || 0) + inherited;
  const bufferMonths = cash / Math.max(1, costs);
  const vitals = {
    Foundation: clamp100(bufferMonths / 6 * 100),                  // 6 months of costs in cash = full
    Habits: clamp100((income - costs) / Math.max(1, income) / 0.20 * 100),  // saving 20% of income = full
    Knowledge: 50, Future: 50, Calm: 50                           // not in the test file → neutral
  };
  return {
    name: c.name || "Customer", income, costs,
    capacity: Math.max(0, income - costs),
    savings: cash, vitals, level: levelOf(vitals), source: CUSTOMER_FILE,
    profile: {
      age: c.age ?? null,
      inheritance: inh.received ? `already received: ${inherited} EUR (included in savings)`
                 : (+inh.amount > 0 ? `expected later: ${+inh.amount} EUR — NOT available, do not plan with it` : "none")
    }
  };
}

/* Assessment JSON (+ the file's intro text) → the app's `user`. */
function assessmentToUser(a, text = "") {
  if (!a.intake) return simpleToUser(a);                  // simple test-case format
  const x = a.intake;
  const sp = x.spending || {};
  const named = (text.match(/assessment for (\w+)/i) || [])[1];
  const vitals = deriveVitals(x);
  return {
    name: x.name && x.name !== "Customer" ? x.name : (named || "Customer"),
    income: x.monthly_income,
    costs: x.monthly_spending,
    capacity: Math.max(0, (x.monthly_saving_cash || 0) + (x.monthly_saving_invested || 0)),
    savings: x.cash,                                   // liquid money only — company shares can't pay a car
    vitals, level: levelOf(vitals),
    source: CUSTOMER_FILE,
    profile: {                                         // extra context for the AI
      age: x.age, profile: x.profile, purpose: x.purpose,
      wealth_total: x.wealth_total, company_share: x.company_share,
      crash_reaction: x.crash_reaction, disability_cover: x.disability_cover, will: x.will,
      goals: x.goals, planned_purchases: sp.planned_purchases || [],
      unused_subscriptions: (sp.subscriptions || []).filter(s => s.last_used_days > 60),
      overspending: (sp.categories || []).filter(c => c.monthly > c.peer_median),
      prediction: a.prediction_agent ? { headline: a.prediction_agent.headline, best_change: a.prediction_agent.best_change } : null,
      coaching_actions: ((a.action_agent || {}).actions || []).map(t => t.title)
    }
  };
}

/* Fetch the file and swap the demo customer for the real one. */
async function loadCustomer() {
  try {
    const r = await fetch(CUSTOMER_FILE, { cache: "no-store" });
    if (!r.ok) throw new Error("HTTP " + r.status);
    const text = await r.text();
    return assessmentToUser(parseAssessment(text), text);
  } catch (e) {
    console.warn("Customer file " + CUSTOMER_FILE + " not loaded — using the demo customer.", e);
    return null;
  }
}
