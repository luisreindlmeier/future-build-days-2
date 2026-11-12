/* =====================================================================
   AI LAYER — the model thinks from the score and the user's own
   description of each plan: costs, monthly costs, loan or no loan, how
   much to save. If there is no key or the call fails, the rule-based
   verdict above stands.
   ===================================================================== */

/* Reasoning models (e.g. GLM on the JUPITER gateway) spend tokens "thinking"
   before the answer — measured ~3000 for one verdict. Keep a generous budget
   or the reply arrives empty with finish_reason "length". 6000 = 2x the
   measured need; higher caps let the model ramble and make
   replies much slower. */
const AI_MAX_TOKENS = 6000;

function getKey() {
  // The key lives only in config.js — never typed by the customer.
  try { localStorage.removeItem("kairos-api-key"); } catch (e) {}   // forget keys saved by older versions
  return CFG.ai.key || "";
}

/* Which AI does this key belong to? */
function providerOf(key) {
  if (key.startsWith("sk-ant")) return "anthropic";
  if (key.startsWith("AIza") || key.startsWith("AQ.")) return "gemini"; // old + new Google key formats
  if (key.startsWith("gsk_")) return "groq";   // Groq: free, very fast, OpenAI-compatible
  if (key.startsWith("sk-bf-")) return "openai"; // hessian.AI / JUPITER gateway (hackathon key)
  return "chatgpt";                              // sk-proj-… / sk-… = OpenAI itself // OpenAI and OpenAI-compatible providers (Mistral, Groq, …)
}

/* One function per provider shape; all return the model's text reply.
   The browser calls the gateway directly (it allows CORS for http:// pages).
   No proxy needed — but the page must NOT be opened as file:// (see askAI). */
async function callProvider(key, system, userContent, geminiModel) {
  let prov = providerOf(key);
  let url, opts;
  if (prov === "anthropic") {
    const A = CFG.ai.anthropic;
    url = A.endpoint;
    opts = { method: "POST", headers: { "content-type": "application/json", "x-api-key": key, "anthropic-version": A.version, "anthropic-dangerous-direct-browser-access": "true" },
      body: JSON.stringify({ model: A.model, max_tokens: AI_MAX_TOKENS, system, messages: [{ role: "user", content: userContent }] }) };
  } else if (prov === "gemini") {
    const G = CFG.ai.gemini;
    opts = { method: "POST", headers: { "content-type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify({ systemInstruction: { parts: [{ text: system }] }, contents: [{ parts: [{ text: userContent }] }],
        generationConfig: { responseMimeType: "application/json", maxOutputTokens: 8192 } }) };   // forces a clean JSON reply
    // which model to use is decided in askJSON (it falls back model by model)
    return await send(G.endpoint.replace("{model}", geminiModel || G.model), opts, prov, G.timeoutMs);
  } else if (prov === "chatgpt") {
    const C = CFG.ai.chatgpt;
    url = C.endpoint;
    const reasoning = /^(gpt-5|o\d)/.test(C.model);          // reasoning models: think briefly, answer fast
    opts = { method: "POST", headers: { "content-type": "application/json", "authorization": "Bearer " + key },
      body: JSON.stringify({ model: C.model, max_completion_tokens: AI_MAX_TOKENS,
        response_format: { type: "json_object" },             // forces a clean JSON reply
        ...(reasoning ? { reasoning_effort: "low" } : {}),
        messages: [{ role: "system", content: system }, { role: "user", content: userContent }] }) };
    prov = "openai";                                          // same reply shape as OpenAI-compatible APIs
  } else {
    const O = prov === "groq" ? CFG.ai.groq : CFG.ai.openai;
    url = O.endpoint;
    opts = { method: "POST", headers: { "content-type": "application/json", "authorization": "Bearer " + key },
      body: JSON.stringify({ model: O.model, max_tokens: AI_MAX_TOKENS, messages: [{ role: "system", content: system }, { role: "user", content: userContent }] }) };
  }
  return await send(url, opts, prov);
}

const AI_TIMEOUT_MS = 90000; // give up after 90 s instead of waiting forever

async function send(url, opts, prov, timeoutMs = AI_TIMEOUT_MS) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  let r;
  try { r = await fetch(url, { ...opts, signal: ctrl.signal }); }
  catch (e) {
    if (e.name === "AbortError") throw new Error("no answer after " + timeoutMs / 1000 + " s — the AI service is too slow right now");
    throw e;
  } finally { clearTimeout(timer); }
  if (!r.ok) {
    let detail = "";
    try { detail = (await r.text()).slice(0, 160); } catch (e) {}
    throw new Error("API " + r.status + (detail ? " — " + detail : ""));
  }
  const data = await r.json();
  if (prov === "anthropic") return (data.content || []).map(c => c.text || "").join("");
  if (prov === "gemini") return (((data.candidates || [])[0] || {}).content || { parts: [] }).parts.map(p => p.text || "").join("");
  const c0 = (data.choices || [])[0] || {};
  const txt = ((c0.message || {}).content || "") + (data.choices || []).slice(1).map(c => (c.message || {}).content || "").join("");
  // Some gateways finish with empty content when reasoning ate the budget — surface it clearly.
  if (!txt.trim() && c0.finish_reason === "length")
    throw new Error("model used all tokens on reasoning — increase max_tokens");
  return txt;
}

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

/* Ask the model, parse the JSON, retry once on a broken reply. */
/* Gemini models whose free daily quota is used up — skipped for the rest
   of this visit so the customer doesn't wait for a model that says no. */
const geminiExhausted = new Set();

async function askJSON(key, system, facts) {
  const content = JSON.stringify(facts);
  if (providerOf(key) !== "gemini") {                 // other providers: one retry on broken JSON
    for (let attempt = 0; ; attempt++) {
      const txt = await callProvider(key, system, content);
      try { return parseVerdict(txt); }
      catch (pe) { if (attempt >= 1) throw pe; console.warn("Kairos AI: unreadable reply", txt); }
    }
  }
  // Gemini (free): try each model in order. Busy, out of quota, too slow or
  // a broken reply → move on to the next model instead of failing.
  const G = CFG.ai.gemini;
  const models = [G.model, ...(G.fallbacks || [])].filter(m => !geminiExhausted.has(m));
  if (!models.length) throw new Error("the free daily AI limit is used up — try again tomorrow");
  let lastErr;
  for (const model of models) {
    try {
      const txt = await callProvider(key, system, content, model);
      try { return parseVerdict(txt); }
      catch (pe) { console.warn("Kairos AI: unreadable reply from " + model, txt); lastErr = pe; continue; }
    } catch (e) {
      lastErr = e;
      if (/^API 429/.test(e.message)) { geminiExhausted.add(model); continue; }   // quota used up
      if (/^(API (500|503|404)|no answer)/.test(e.message)) continue;          // busy / gone / too slow
      throw e;                                                                  // real error (bad key…) → stop
    }
  }
  if (lastErr && /^API 429/.test(lastErr.message)) throw new Error("the free daily AI limit is used up — try again tomorrow");
  throw lastErr;
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
  const key = getKey();
  if (!key) { out.innerHTML = aiError("Kairos AI is not available right now."); return; }

  const p = projects[i];
  if (!(p.idea || "").trim()) {
    out.innerHTML = aiError("Describe your plan in the box above first — what, where, how much, when. Kairos AI does the rest.");
    return;
  }
  btn.disabled = true; const old = btn.textContent; btn.textContent = "Kairos is thinking…";

  const facts = {
    client: { name: user.name, income: user.income, monthly_costs: user.costs, saving_capacity: user.capacity, savings: user.savings, vitals: user.vitals, level: user.level },
    customer_profile: user.profile || null,           // age, wealth, habits, planned purchases… from the assessment
    affordability: affordability(user, { ...p, targetM: 0 }),   // HARD limits computed by the bank
    project: { type: p.type, name: p.name },
    description: p.idea.trim().slice(0, 1500),
    rules: CFG.caps, rates: CFG.rates, market: CFG.market,
    city_prices_eur_sqm: CFG.cities, today: "Nov 2026"
  };

  try {
    p.plan = fixPlan(await askJSON(key, AI_PLAN_SYSTEM, facts), p);
    p.planHidden = false;                              // a fresh answer is always shown open
    render();                                          // refresh verdict chip, counters, donut, advisor + save
    return;
  } catch (e) {
    out.innerHTML = aiError(aiFailMsg(e));
  }
  btn.disabled = false; btn.textContent = old;
}
