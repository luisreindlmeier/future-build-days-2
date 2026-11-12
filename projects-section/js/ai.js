/* Parse the model's reply: grab the outermost {…} and try JSON.parse;
   if it still fails, repair the common breakages (unescaped inner
   double quotes, trailing commas) before giving up. */
function parseVerdict(txt) {
  const s = txt.indexOf("{"), e = txt.lastIndexOf("}");
  if (s < 0 || e <= s) throw new Error("no JSON in reply");
  const raw = txt.slice(s, e + 1);
  try { return JSON.parse(raw); } catch (err) { /* fall through to repair */ }
  let fixed = raw.replace(/,\s*([}\]])/g, "$1");   // trailing commas
  try { return JSON.parse(fixed); } catch (err) { /* next repair */ }
  // Unescaped double quotes inside string values: a closing quote that is
  // NOT followed by , } ] or : is really an inner quote — escape it.
  let out = "", inStr = false;
  for (let k = 0; k < fixed.length; k++) {
    const ch = fixed[k];
    if (!inStr) { out += ch; if (ch === '"') inStr = true; continue; }
    if (ch === "\\") { out += ch + (fixed[k + 1] || ""); k++; continue; }
    if (ch === '"') {
      let n = k + 1; while (n < fixed.length && /\s/.test(fixed[n])) n++;
      const next = fixed[n];
      if (next && !",}]:".includes(next)) { out += '\\"'; continue; }  // inner quote
      inStr = false; out += ch; continue;
    }
    out += ch;
  }
  try { return JSON.parse(out); } catch (err) {
    throw new Error("AI reply was not valid JSON — try again");
  }
}

/* Turn a caught AI error into the message shown under the project. */
function aiFailMsg(e) {
  const hint = e instanceof TypeError
    ? (location.protocol === "file:"
        ? "The page was opened as a file, so the browser blocks the AI call. Open it with VS Code <b>Live Server</b> (right-click index.html → Open with Live Server)."
        : "Network blocked — check your internet connection.")
    : "";
  return "Kairos AI couldn't answer (" + e.message + "). Please try again in a moment." + (hint ? "<br>" + hint : "");
}

function aiError(msg) {
  return `<div class="ai-panel"><div class="ai-head"><span class="ai-badge">AI</span><b>Kairos AI</b></div>
    <p class="sub" style="font-size:13.5px">${msg}</p></div>`;
}

/* =====================================================================
   AI PLANNER — works for every project type. The user describes the plan
   in their own words ("a 3-room flat in Munich near the S-Bahn",
   "two weeks in Japan with my partner", "a pizza restaurant in Cologne");
   the AI estimates one-time costs, monthly costs, whether a bank loan
   fits, and how much to save. Totals, loan payment and profit are
   RE-COMPUTED here (fixPlan), so the numbers on screen always add up.
   ===================================================================== */
const AI_PLAN_SYSTEM = `You are Kairos, Deutsche Bank's honest financial-planning coach for young clients in Germany.
You receive JSON with the client's finances (income, costs, saving capacity, savings, five vitals 0-100), ONE life project (project.type, the values the user set with sliders, project.targetM = months from today), the user's own description of the plan (description, may be empty), the bank's rules, rates and market data.
THINK like an experienced German advisor using realistic Nov 2026 prices in EUR.
The description is the ONLY input from the user: it says what they want, and maybe how much they want to spend and when.
- If they name a price or budget, compare it with your realistic estimate and say if it is too low or too high (both numbers).
- If they name a date, put the months from Nov 2026 until then in target_months. If they give no date, choose the earliest realistic month and use it.
- If something is missing, assume something typical and say it in a few words.
Estimate:
- one_time_costs: 3-8 concrete line items paid once (purchase price, fees, deposits, equipment, flights...).
- monthly_costs: 0-8 line items that keep coming every month BECAUSE of this project (insurance, fuel, maintenance, rent, staff, childcare...). Never include a loan payment here.
By type:
- car: price, registration, first-year extras; monthly insurance, tax, fuel or charging, maintenance, parking. Loan: at most 80% of the price, ${(CFG.rates.carLoan * 100).toFixed(1)}%, 2-5 years; loan payment + monthly costs must stay <= 15% of income.
- home: price (city and size from the description with city_prices_eur_sqm; if missing assume 50 m2 in an average city), purchase costs 12% (land transfer tax, notary, agent), renovation, moving; monthly Hausgeld/maintenance, utilities, insurance. Loan = mortgage at ${(CFG.rates.mortgage * 100).toFixed(2)}%, 25-30 years; payment must stay <= 35% of income; equity should cover the purchase costs plus at least 10% of the price.
- business: start-up costs (deposit, renovation, equipment, permits, first stock, marketing, legal setup, cash reserve); monthly rent, staff, stock, utilities, insurance, accounting, a modest owner salary. Also estimate monthly_revenue after ramp-up and break_even_months. Keep 6 months of personal living costs private (not for the business); own contribution >= 15% of start-up costs; loan payment must be covered by business profit with a 30% margin. Loans: KfW StartGeld (up to 125000 EUR) or KfW ERP-Gruenderkredit via Deutsche Bank, ${(CFG.rates.bizLoan * 100).toFixed(1)}%, 5-10 years.
- studies: tuition, flights, deposit, visa; monthly rent, food, insurance, transport. Loan only a KfW student loan and only if savings cannot cover it.
- trip, family, sabbatical: NEVER a loan; savings only. Family: monthly costs of a child (food, clothes, childcare minus Kindergeld 255 EUR). Sabbatical: monthly living costs while not earning.
THE CUSTOMER'S REAL MONEY DECIDES. affordability holds hard limits the bank computed from the customer's real income, costs, cash and saving capacity:
- Never recommend a loan above affordability.max_loan, or any loan if loan_allowed is false.
- affordability.max_price_if_ready_in gives the most the customer can pay (own savings + allowed loan) for each horizon. The emergency_buffer_kept is never spent.
- If your estimate is above the limit for target_months, the verdict is not_yet: say plainly that it does not fit their income and either suggest a smaller version within the limit or a later target_months where it fits.
- monthly_saving can never exceed saving_capacity.
Use customer_profile (age, inheritance — only money already received counts, total wealth vs. liquid cash, company concentration, crash behaviour, overspending, unused subscriptions, planned purchases, the coaching actions already suggested) to make the advice personal: e.g. free money by cancelling unused subscriptions before suggesting a loan.
Hard rules for every type: Foundation vital under 40 means no loan at all. If a loan does not fit now, say in which year it would (income grows 3%/yr, savings grow).
Also give monthly_saving (per month until the target, within saving capacity) and ready ("Mon YYYY").
Round EUR to integers. Check your arithmetic. Be honest and warm; if the plan is too big, suggest a smaller version.
KEEP IT SHORT — people skim: summary max 2 short sentences (35 words), 3-5 cost lines per list with names of max 5 words, max 2 risks of max 12 words, loan.reason max 15 words.
Reply with ONLY one JSON object, no markdown. Inside strings use single quotes, never double quotes.
{"verdict":"good"|"adjust"|"not_yet","summary":string,"target_months":int,"one_time_costs":[{"item":string,"eur":int}],"monthly_costs":[{"item":string,"eur":int}],"monthly_revenue":int,"break_even_months":int,"loan":{"recommended":bool,"amount":int,"years":int,"product":string,"reason":string},"monthly_saving":int,"ready":"Mon YYYY","risks":[string]}`;

const esc = t => String(t ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const num = v => Math.max(0, Math.round(+v || 0));

/* Yearly loan rate per project type (null = Kairos never lends for it). */
function loanRate(type) {
  if (PROJECT_TYPES[type].noLoan) return null;
  return { car: CFG.rates.carLoan, home: CFG.rates.mortgage, business: CFG.rates.bizLoan, studies: CFG.rates.studiesLoan }[type] ?? CFG.rates.bizLoan;
}

/* When is the own share saved? Computed, not guessed by the AI:
   free cash today + monthly saving, the emergency buffer stays untouched. */
function readyDate(own, aff, monthlySaving) {
  const missing = own - aff.free_cash_now;
  if (missing <= 0) return "now";
  const perMonth = Math.min(monthlySaving || aff.saving_capacity, aff.saving_capacity);
  if (perMonth <= 0) return "never at today's income";
  const m = Math.ceil(missing / perMonth);
  return m > 600 ? "not within 50 years" : ym(m);
}

/* Re-compute every derived number so the plan is internally consistent,
   and ENFORCE the bank's affordability limits on the AI's answer. */
function fixPlan(a, p) {
  const lines = arr => (Array.isArray(arr) ? arr : [])
    .map(x => ({ item: String((x && x.item) || "—"), eur: num(x && x.eur) })).filter(x => x.eur > 0);
  const once = lines(a.one_time_costs || a.startup_costs), monthly = lines(a.monthly_costs);
  const onceTotal = once.reduce((s, x) => s + x.eur, 0);
  const monthlyTotal = monthly.reduce((s, x) => s + x.eur, 0);
  p.targetM = Math.min(360, Math.max(1, num(a.target_months) || 12));   // the date comes from the description now
  const aff = affordability(user, p);
  const rate = loanRate(p.type);
  const isBiz = p.type === "business";
  const revenue = isBiz ? num(a.monthly_revenue) : 0;
  const loan = a.loan || {};
  const checks = [];                                           // what the bank check changed or found
  const years = Math.min(35, Math.max(1, num(loan.years) || (p.type === "home" ? 30 : 5)));

  let loanAmount = loan.recommended && aff.loan_allowed ? Math.min(num(loan.amount), onceTotal) : 0;
  if (loan.recommended && !aff.loan_allowed)
    checks.push(["bad", "Loan removed by the bank check: " + aff.loan_block_reason]);
  // personal limit (income-based)
  if (loanAmount > aff.max_loan) {
    checks.push(["bad", `Loan cut from ${eur(loanAmount)} to ${eur(aff.max_loan)}: with ${eur(user.income)} income the payment may be at most ${eur(aff.max_loan_payment ?? 0)}/month.`]);
    loanAmount = aff.max_loan;
  }
  // business: the payment must be covered by the business's own profit with a 30% margin
  if (isBiz && loanAmount) {
    const payCap = Math.max(0, (revenue - monthlyTotal) / 1.3);
    const cap = Math.round(maxLoanFor(payCap, rate, years * 12));
    if (loanAmount > cap) {
      checks.push(["bad", `Loan cut from ${eur(loanAmount)} to ${eur(cap)}: the business's expected profit only covers about ${eur(payCap)}/month of repayment.`]);
      loanAmount = cap;
    }
  }
  const payment = loanAmount ? Math.round(annuity(loanAmount, rate, years * 12)) : 0;
  const own = onceTotal - loanAmount;

  let verdict = ["good", "adjust", "not_yet"].includes(a.verdict) ? a.verdict : "adjust";
  if (own > aff.saved_by_target) {
    verdict = "not_yet";
    checks.push(["bad", `You need ${eur(own)} of your own money, but by ${aff.target_date} you will have about ${eur(aff.saved_by_target)} (${eur(aff.free_cash_now)} free cash today + ${eur(user.capacity)}/month; ${eur(aff.emergency_buffer_kept)} stays as your emergency buffer).`]);
  }
  if (!isBiz && monthlyTotal + payment > Math.max(0, aff.monthly_free)) {
    if (verdict === "good") verdict = "adjust";
    checks.push(["warn", `This plan costs ${eur(monthlyTotal + payment)} every month, but only ${eur(Math.max(0, aff.monthly_free))} is left of your income today — other spending would have to go.`]);
  }
  let monthlySaving = num(a.monthly_saving);
  if (monthlySaving > user.capacity) {
    checks.push(["warn", `The AI suggested saving ${eur(monthlySaving)}/month; you can put aside ${eur(user.capacity)}, so that is the most it can be.`]);
    monthlySaving = user.capacity;
  }
  if (!checks.length) checks.push(["ok", `Fits your numbers: own share ${eur(own)} of ${eur(aff.saved_by_target)} available by ${aff.target_date}${payment ? `, loan payment ${eur(payment)} of max ${eur(aff.max_loan_payment ?? payment)}/month` : ""}.`]);

  return {
    verdict, summary: String(a.summary || ""),
    once, monthly, onceTotal, monthlyTotal, revenue, rate,
    profit: revenue - monthlyTotal - payment,                  // business only
    perMonth: monthlyTotal + payment,                          // what it costs every month incl. the loan
    breakEven: isBiz ? (num(a.break_even_months) || null) : null,
    own, checks,
    loan: { recommended: loanAmount > 0, amount: loanAmount, years, payment,
            product: String(loan.product || ""),
            reason: !aff.loan_allowed ? aff.loan_block_reason : String(loan.reason || "") },
    monthlySaving, ready: readyDate(own, aff, monthlySaving),
    risks: (Array.isArray(a.risks) ? a.risks : []).map(String).slice(0, 2)
  };
}

function planHTML(p, i) {
  const a = p.plan;
  if (!a.once) return "";                                        // plan saved by an older version
  const head = `<div class="ai-head"><span class="ai-badge">AI</span><b>Kairos plan</b>
      ${chip(a.verdict === "not_yet" ? "bad" : a.verdict === "adjust" ? "warn" : "good")}
      <button class="ai-toggle" data-toggleplan="${i}" type="button" aria-expanded="${!p.planHidden}">${p.planHidden ? "Show advice ▾" : "Hide ▴"}</button></div>`;
  if (p.planHidden) return `<div class="ai-panel ai-collapsed">${head}</div>`;
  const isBiz = p.type === "business";
  const rows = list => list.map(x => `<tr><td>${esc(x.item)}</td><td class="num">${eur(x.eur)}</td></tr>`).join("");
  const table = list => `<table class="biz">${rows(list)}<tr class="tot"><td>Total</td><td class="num">${eur(list.reduce((s, x) => s + x.eur, 0))}</td></tr></table>`;
  const loan = a.loan;
  const loanTxt = loan.recommended
    ? `<b>Bank loan: ${eur(loan.amount)}</b> over ${loan.years} years ≈ <b>${eur(loan.payment)}/month</b> (at ${(a.rate * 100).toFixed(2).replace(/0$/, "")}%)${loan.product ? " · " + esc(loan.product) : ""}. ${esc(loan.reason)}`
    : `<b>No loan</b> — ${esc(loan.reason) || "fund it from savings."}`;
  const pctIncome = Math.round(a.perMonth / user.income * 100);
  const kpis = isBiz
    ? [["Start-up cost", eur(a.onceTotal)], ["Monthly costs", eur(a.monthlyTotal)], ["Revenue / month", eur(a.revenue)],
       ["Profit / month", `<span style="color:${a.profit >= 0 ? "var(--good)" : "var(--bad)"}">${a.profit < 0 ? "−" : ""}${eur(Math.abs(a.profit))}</span>`]]
    : [["One-time cost", eur(a.onceTotal)], ["Monthly costs", eur(a.monthlyTotal)],
       ["Loan / month", loan.recommended ? eur(loan.payment) : "—"],
       ["Every month", `${eur(a.perMonth)}<small> · ${pctIncome}% of income</small>`]];
  return `<div class="ai-panel">
    ${head}
    <p style="font-size:14px;line-height:1.6">${esc(a.summary)}</p>
    <div class="ai-kpis">${kpis.map(([k, v]) => `<span class="ai-kpi">${k}<b>${v}</b></span>`).join("")}</div>
    <div class="grid2 biz-tables">
      <div><div class="label">${isBiz ? "One-time start-up costs" : "One-time costs"}</div>${table(a.once)}</div>
      <div><div class="label">${isBiz ? "Monthly running costs" : "Monthly costs after"}</div>
        ${a.monthly.length ? table(a.monthly) : `<p class="sub" style="font-size:13px">No ongoing monthly costs.</p>`}</div>
    </div>
    <div class="label">Bank check — your real numbers</div>
    ${(a.checks || []).map(([k, t]) => `<div class="reason">${dot(k)}<span>${t}</span></div>`).join("")}
    <div class="label">Financing</div>
    <p class="sub" style="font-size:13.5px">${loanTxt}</p>
    <p class="sub" style="font-size:13.5px;margin-top:6px">Your own share: <b>${eur(a.own)}</b> · save <b>${eur(a.monthlySaving)}/month</b> · ready <b>${esc(a.ready)}</b>${a.breakEven ? ` · break-even after about <b>${a.breakEven} months</b>` : ""}.</p>
    ${a.risks.length ? `<div class="label">Watch out</div>` + a.risks.map(r => `<div class="reason">${dot("warn")}<span>${esc(r)}</span></div>`).join("") : ""}
    <p class="sub" style="font-size:11.5px;margin-top:8px">AI estimate for orientation only — check real offers with a Deutsche Bank advisor.</p>
  </div>`;
}

async function askAI(i) {
  const out = document.getElementById("ai" + i);
  const btn = document.querySelector(`[data-ai="${i}"]`);

  const p = projects[i];
  if (!(p.idea || "").trim()) {
    out.innerHTML = aiError("Describe your plan in the box above first — what, where, how much, when. Kairos AI does the rest.");
    return;
  }
  btn.disabled = true; const old = btn.textContent; btn.textContent = "Kairos is thinking…";

  try {
    const customerURL = new URL(CUSTOMER_FILE, location.href);
    if (!/\/api\/users\/[^/]+\/kairos$/.test(customerURL.pathname)) {
      throw new Error("Open a customer connected to the backend before requesting a plan.");
    }
    customerURL.pathname = customerURL.pathname.replace(/\/kairos$/, '/projects/plan');
    customerURL.search = '';
    const response = await fetch(customerURL, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({type: p.type, name: p.name, description: p.idea.trim().slice(0, 1500)}),
      signal: AbortSignal.timeout(190000)
    });
    if (!response.ok) throw new Error('Planner unavailable (HTTP ' + response.status + ').');
    const result = await response.json();
    if (!result.plan) throw new Error(result.message || 'AI estimate unavailable.');
    p.plan = result.plan;
    p.targetM = result.targetM;
    p.planHidden = false;                              // a fresh answer is always shown open
    render();                                          // refresh verdict chip, counters, donut, advisor + save
    return;
  } catch (e) {
    out.innerHTML = aiError(esc(e.message));
  }
  btn.disabled = false; btn.textContent = old;
}
