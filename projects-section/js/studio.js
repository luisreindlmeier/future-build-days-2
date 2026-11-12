'use strict';
/* Kairos studio: watch the AI agents work, create your own profile, personalise it.
   Loaded before dashboard.js; uses its helpers ($, esc, money, api, header, notify, load, workspace, customer). */
const PROFILE_API = 'http://localhost:8080/api/profiles';
const CATEGORIES = [['HOUSING', 'Housing'], ['GROCERIES', 'Groceries'], ['TRANSPORT', 'Transport'], ['EATING_OUT', 'Eating out'],
  ['SHOPPING', 'Shopping'], ['TRAVEL', 'Travel'], ['SUBSCRIPTIONS', 'Subscriptions'], ['OTHER', 'Other']];
const STAGES = [['pro', 'Young professional'], ['founder', 'Founder / self-employed'], ['heir', 'Heir / family business']];
const PURPOSES = ['Security', 'Freedom', 'A home of my own', 'Family', 'Building something', 'Independence', 'Early retirement'];
const BLANK = {name: '', age: 30, lifeStage: 'pro', purpose: 'Security', situation: '', riskTolerance: 'BALANCED',
  monthlyIncome: 3500, incomeNote: '', spending: {HOUSING: 1100, GROCERIES: 350, TRANSPORT: 150, EATING_OUT: 250, SHOPPING: 200,
  TRAVEL: 100, SUBSCRIPTIONS: 50, OTHER: 100}, cashSavings: 5000, investments: 0, companyShares: 0, monthlySavingCash: 300,
  monthlySavingInvested: 0, crashReaction: 'hold', disabilityCover: false, will: false, confidence: 3, knowledge: 4, shockAbsorb: 2,
  horizonYears: 15, goals: [{type: 'wealth', target: 250000, priority: 1}], subscriptions: [], plannedPurchases: []};
let profiles = [], formState = null, formMode = 'create', formFor = null;

/* ---------------------------------------------------------------- customer picker */
async function refreshCustomers() {
  try {
    profiles = await (await fetch(PROFILE_API)).json();
  } catch (e) { return; }
  const sel = $('customer');
  const demo = profiles.filter(p => !p.custom), mine = profiles.filter(p => p.custom);
  sel.innerHTML = `<optgroup label="Demo customers">${demo.map(p => `<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('')}</optgroup>`
    + (mine.length ? `<optgroup label="Your profiles">${mine.map(p => `<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('')}</optgroup>` : '');
  sel.value = customer;
}
const isCustom = id => profiles.some(p => p.id === id && p.custom);
function switchTo(id, hash) {
  customer = id;
  const url = new URL(location.href);
  url.search = '?user=' + encodeURIComponent(id);
  url.hash = hash;
  window.history.replaceState(null, '', url);
  $('customer').value = id;
  load(true);
}

/* ---------------------------------------------------------------- AI agents at work */
const FIELD = k => k === '*' ? 'whole answer' : k.replace(/_/g, ' ').replace(/\[(\d+)\]/, (m, i) => ' #' + (+i + 1));
const secs = v => v == null ? '' : (v < 1 ? '<1 s' : v.toFixed(1) + ' s');
function sourcePill(s) {
  const map = {ai: ['green', 'Written by AI, all checks passed'], ai_partial: ['amber', 'AI + some parts replaced by rules'],
    fallback: ['amber', 'Rule-based text (AI not used)'], rules: ['', 'Rule-based text']};
  const [c, t] = map[s] || ['', esc(s || 'waiting')];
  return `<span class="pill ${c}">${t}</span>`;
}
function attempts(result) {
  const att = (result.validation || {}).attempts || [];
  if (!att.length) return `<p class="sub">No AI call: ${esc((result.problems || [])[0] || 'rule-based text')}.</p>`;
  return `<ol class="attempts">${att.map(a => {
    const v = Object.entries(a.violations || {});
    const fixed = (a.auto_qualified || []).map(FIELD);
    return `<li><div class="att-head"><b>Attempt ${a.attempt}</b><span>${secs(a.seconds)}</span></div>
      ${v.length ? `<p class="caught">Guardrail caught ${v.reduce((n, [, m]) => n + m.length, 0)} problem${v.length > 1 || v[0][1].length > 1 ? 's' : ''}:</p>
        <ul class="viol">${v.map(([f, ms]) => ms.map(m => `<li><b>${esc(FIELD(f))}</b> · ${esc(m)}</li>`).join('')).join('')}</ul>
        ${a.attempt === 1 ? '<p class="sub">→ Sent back to the model with this list, asking it to fix exactly these.</p>' : ''}`
        : '<p class="passed">✓ Every number traced to the simulation, wording and scenario checks passed.</p>'}
      ${fixed.length ? `<p class="sub">Auto-fix: added “in the simulation” where a risk really is 0% (${esc(fixed.join(', '))}).</p>` : ''}</li>`;
  }).join('')}</ol>${Object.keys(result.validation.replaced_fields || {}).length
    ? `<p class="caught">Replaced by rule-based text: ${esc(Object.keys(result.validation.replaced_fields).map(FIELD).join(', '))}</p>` : ''}`;
}
function agentCard(title, role, result, preview) {
  if (!result) return `<section class="card"><p class="eyebrow">${esc(role)}</p><h2>${esc(title)}</h2><p class="sub">Not run for this customer.</p></section>`;
  return `<section class="card agent-card"><div class="card-head"><div><p class="eyebrow">${esc(role)}</p><h2>${esc(title)}</h2>
    <p class="sub">${esc(result.model || 'no model')} · ${secs(result.seconds)} total</p></div>${sourcePill(result.source)}</div>
    ${attempts(result)}<div class="preview">${preview}</div></section>`;
}
function intakeTable(i) {
  const g = (i.goals || []).map(x => x.type === 'keep' ? 'Not end below today' : x.type === 'home' ? `Home: ${money(x.target)} in ${x.years} years` : `Wealth: ${money(x.target)}`);
  const rows = [['Age · life stage', `${i.age} · ${({pro: 'young professional', founder: 'founder', heir: 'heir'})[i.profile] || i.profile}`],
    ['Money is for', i.purpose], ['Income · spending', `${money(i.monthly_income)} · ${money(i.monthly_spending)} a month`],
    ['Saving', `${money(i.monthly_saving_cash)} to cash · ${money(i.monthly_saving_invested)} invested a month`],
    ['Wealth · cash', `${money(i.wealth_total)} · ${money(i.cash)}`], ['In one company', Math.round((i.company_share || 0) * 100) + '%'],
    ['Crash test', ({sell: 'sold everything', hold: 'held', buy: 'bought more'})[i.crash_reaction]],
    ['Cover · will', `${i.disability_cover ? 'covered' : 'no disability cover'} · ${i.will ? 'will in place' : 'no will'}`],
    ['Goals', g.join(' · ')], ['Horizon', `${i.horizon_years} years`],
    ['Spending data', `${(i.spending?.categories || []).length} categories vs peers · ${(i.spending?.subscriptions || []).length} subscriptions · ${(i.spending?.planned_purchases || []).length} planned purchases`]];
  return `<table class="facts">${rows.map(([k, v]) => `<tr><th>${esc(k)}</th><td>${esc(v)}</td></tr>`).join('')}</table>`;
}
function engineTable(e) {
  const main = [...(e.customer?.goals || [])].sort((a, b) => a.priority - b.priority)[0];
  return `<div class="scroll"><table class="facts"><tr><th>Scenario</th><th>Range at the horizon</th><th>Middle</th><th>Goal chance</th><th>Ends below today</th></tr>
    ${(e.scenarios || []).map(s => `<tr><td>${esc(s.label)}</td><td>${esc(s.results.range)}</td><td>${esc(s.results.middle)}</td>
      <td>${esc(main ? s.results.goal_success[main.id] : '')}</td><td>${esc(s.results.risk_below_today)}</td></tr>`).join('')}</table></div>`;
}
function agents() {
  const head = header('Watch the AI agents work.', 'Every number comes from the simulation. The AI only writes the words, and a guardrail checks them before you see them.', 'AI AGENTS AT WORK');
  const p = workspace.prediction;
  const t = p.engine?.timings || {};
  const running = p.status === 'RUNNING';
  const step = (n, label, state, s) => `<div class="step ${state}"><span>${n}</span><b>${label}</b><small>${state === 'running' ? 'working…' : state === 'done' ? secs(s) || 'done' : state === 'off' ? 'not available' : ''}</small></div>`;
  const st = running ? 'running' : p.status === 'READY' ? 'done' : 'off';
  let html = head + `<div class="pipeline">${step(1, 'Your data', 'done')}${step(2, 'Simulation engine · 2,000 futures', st, t.engine_seconds)}
    ${step(3, 'Prediction agent', st, t.prediction_seconds)}${step(4, 'Action agent', st, t.action_seconds)}${step(5, 'Guardrail → you', st)}</div>`;
  if (running) return html + `<div class="card empty"><h2>The agents are working on ${esc(workspace.tree.name)}’s picture.</h2><p class="sub">Simulating 2,000 futures per scenario, then writing and checking the explanations. This page updates by itself.</p></div>`;
  if (p.status !== 'READY') return html + `<div class="card empty"><h2>The agents are unavailable right now.</h2><p class="sub">${esc(p.error || '')}</p><button class="button secondary" data-studio="rerun">Try again</button></div>`;
  const pr = p.prediction, ac = p.actions;
  html += `<div class="grid columns" style="margin-top:22px"><section class="card"><p class="eyebrow">STEP 1 · WHAT THE AGENTS RECEIVE</p><h2>Your financial facts</h2>
      <p class="sub">Sent as “Customer”: your name never goes to the AI.</p>${intakeTable(p.intake)}</section>
    <section class="card"><p class="eyebrow">STEP 2 · SIMULATION ENGINE</p><h2>${(p.engine?.paths || 2000).toLocaleString('en')} possible futures per scenario</h2>
      <p class="sub">Same futures for every scenario · ${secs(t.engine_seconds)}</p><p class="eyebrow" style="margin-top:16px">CHANCE OF REACHING THE MAIN GOAL</p>${goalBars(p.engine || {})}
      <details><summary>All scenario numbers</summary>${engineTable(p.engine || {})}</details></section></div>
    <section class="card" style="margin-top:22px"><p class="eyebrow">TIME PER STEP</p><h2>Engine first, then both agents in parallel</h2>${timingBars(p)}</section>
    <div class="grid columns" style="margin-top:22px">
    ${agentCard('Prediction agent', 'STEP 3 · WHAT CAN HAPPEN', pr, pr ? `<p class="eyebrow">WHAT YOU SEE</p><h3>${esc(pr.output.headline)}</h3><p>${esc(pr.output.future_selves?.with_changes || '')}</p><a class="link" href="#future">Open My future →</a>` : '')}
    ${agentCard('Action agent', 'STEP 4 · WHAT TO DO NEXT', ac, ac ? `<p class="eyebrow">WHAT YOU SEE</p><h3>${esc(ac.output.intro)}</h3><ol class="list">${ac.output.actions.slice(0, 4).map(a => `<li>${esc(a.title)}</li>`).join('')}</ol><a class="link" href="#actions">Open My next steps →</a>` : '')}</div>
    <section class="card" style="margin-top:22px"><p class="eyebrow">STEP 5 · THE GUARDRAIL</p><h2>Checked before you see it</h2><ul class="list">
      <li>Every €, %, point difference and duration must appear in the simulation’s facts, for the scenario named in that sentence.</li>
      <li>No promises, no buy/sell advice, no marketing words; a risk is only “removed” if it is 0% in the simulation.</li>
      <li>On a problem the model gets one retry with the list; parts that still fail are replaced by rule-based text.</li></ul>
      <div class="demo-controls"><button class="button secondary" data-studio="rerun">Run the agents again →</button><small>A fresh AI run for this customer. The numbers stay the same; the wording may change.</small></div>
      <details><summary>Raw data: intake, engine facts and checks</summary><pre>${esc(JSON.stringify({intake: p.intake, derived: pr?.derived, prediction_validation: pr?.validation, action_validation: ac?.validation, timings: t}, null, 1))}</pre></details></section>`;
  return html;
}

/* ---------------------------------------------------------------- create / personalise */
const field = (label, input, hint = '') => `<label class="field"><span>${label}</span>${input}${hint ? `<small>${hint}</small>` : ''}</label>`;
const num = (name, v, attrs = '') => `<input type="number" name="${name}" value="${esc(v ?? '')}" ${attrs}>`;
const opt = (pairs, v) => pairs.map(([k, l]) => `<option value="${esc(k)}" ${k === v ? 'selected' : ''}>${esc(l)}</option>`).join('');
function goalRow(i, g) {
  g = g || {type: i ? '' : 'wealth'};
  return `<div class="row three goal" data-goal="${i}">${field(i ? 'Second goal (optional)' : 'Main goal', `<select name="g${i}type">${i ? '<option value="">None</option>' : ''}${opt([['wealth', 'Build wealth'], ['home', 'Save for a home'], ['keep', 'Not end below today']], g.type)}</select>`)}
    ${field('Target €', num(`g${i}target`, g.target, 'min="1000" step="1000"'))}${field('In years (home)', num(`g${i}years`, g.years, 'min="1" max="30"'))}</div>`;
}
function subRow(i, s) {
  s = s || {};
  return `<div class="row three">${field(i ? '' : 'Subscription', `<input name="s${i}name" value="${esc(s.name || '')}" maxlength="40" placeholder="e.g. Gym">`)}
    ${field(i ? '' : '€ a month', num(`s${i}monthly`, s.monthly, 'min="0" step="1"'))}${field(i ? '' : 'Last used (days ago)', num(`s${i}days`, s.lastUsedDays, 'min="0"'))}</div>`;
}
function profileForm(r) {
  const spendTotal = Object.values(r.spending || {}).reduce((a, b) => a + (+b || 0), 0);
  const p0 = (r.plannedPurchases || [])[0] || {};
  return `<form id="profileForm" class="profile-form" novalidate>
  <fieldset class="card"><legend><span>1</span> About you</legend><div class="row three">
    ${field('First name', `<input name="name" value="${esc(r.name)}" maxlength="40" required autocomplete="given-name">`)}
    ${field('Age', num('age', r.age, 'min="18" max="85" required'))}
    ${field('Life stage', `<select name="lifeStage">${opt(STAGES, r.lifeStage)}</select>`)}</div><div class="row">
    ${field('My money is mainly for', `<input name="purpose" list="purposes" value="${esc(r.purpose)}" maxlength="60"><datalist id="purposes">${PURPOSES.map(x => `<option value="${esc(x)}">`).join('')}</datalist>`)}
    ${field('Comfort with risk', `<select name="riskTolerance">${opt([['CAUTIOUS', 'Cautious'], ['BALANCED', 'Balanced'], ['GROWTH', 'Growth']], r.riskTolerance)}</select>`)}</div>
    ${field('Your situation in your own words (optional)', `<textarea name="situation" maxlength="400" rows="2" placeholder="e.g. I just started my first job and want to buy a flat.">${esc(r.situation || '')}</textarea>`)}</fieldset>
  <fieldset class="card"><legend><span>2</span> Income and spending</legend><div class="row">
    ${field('Net income € a month', num('monthlyIncome', r.monthlyIncome, 'min="300" step="50" required'))}
    ${field('About your income (optional)', `<input name="incomeNote" value="${esc(r.incomeNote || '')}" maxlength="80" placeholder="e.g. salary + bonus">`)}</div>
    <p class="sub">Spending € a month, by category · total <b id="spendTotal">${money(spendTotal)}</b></p><div class="row four">
    ${CATEGORIES.map(([k, l]) => field(l, num('sp_' + k, (r.spending || {})[k] ?? 0, 'min="0" step="10"'))).join('')}</div><div class="row">
    ${field('You save to your account € a month', num('monthlySavingCash', r.monthlySavingCash, 'step="10"'), 'Negative if you spend more than you earn')}
    ${field('You invest € a month', num('monthlySavingInvested', r.monthlySavingInvested, 'min="0" step="10"'))}</div>
    <p class="sub" id="leftOver"></p></fieldset>
  <fieldset class="card"><legend><span>3</span> What you own</legend><div class="row three">
    ${field('Cash savings €', num('cashSavings', r.cashSavings, 'min="0" step="100"'))}
    ${field('Funds, ETFs, pension €', num('investments', r.investments, 'min="0" step="1000"'))}
    ${field('Shares in one company €', num('companyShares', r.companyShares, 'min="0" step="1000"'), 'Family company, own start-up or employer shares')}</div></fieldset>
  <fieldset class="card"><legend><span>4</span> Habits and protection</legend>
    <p class="question">Markets fall 30% in one week and the news is full of it. What do you do with your investments?</p>
    <div class="choices">${[['sell', 'Sell everything'], ['hold', 'Hold and wait'], ['buy', 'Buy a little more']].map(([k, l]) => `<label class="choice"><input type="radio" name="crashReaction" value="${k}" ${r.crashReaction === k ? 'checked' : ''}><span>${l}</span></label>`).join('')}</div>
    <div class="row three">${field('How on top of your money do you feel?', `<input type="range" name="confidence" min="1" max="5" value="${esc(r.confidence)}">`, '1 not at all · 5 completely')}
    ${field('Your financial knowledge', `<input type="range" name="knowledge" min="1" max="7" value="${esc(r.knowledge)}">`, '1 beginner · 7 expert')}
    ${field('An unexpected €2,000 bill tomorrow?', `<select name="shockAbsorb">${opt([['1', 'I certainly could not pay it'], ['2', 'I probably could not'], ['3', 'I probably could'], ['4', 'I certainly could']], String(r.shockAbsorb))}</select>`)}</div>
    <div class="checks"><label><input type="checkbox" name="disabilityCover" ${r.disabilityCover ? 'checked' : ''}> I have disability / income protection cover</label>
    <label><input type="checkbox" name="will" ${r.will ? 'checked' : ''}> I have a will</label></div></fieldset>
  <fieldset class="card"><legend><span>5</span> Your goals</legend>${field('Look how far ahead (years)', num('horizonYears', r.horizonYears, 'min="3" max="30"'))}
    ${goalRow(0, (r.goals || [])[0])}${goalRow(1, (r.goals || [])[1])}</fieldset>
  <fieldset class="card"><legend><span>6</span> Subscriptions and plans <small>optional</small></legend>
    ${[0, 1, 2, 3, 4].map(i => subRow(i, (r.subscriptions || [])[i])).join('')}
    <div class="row three">${field('A big purchase you plan', `<input name="p0label" value="${esc(p0.label || '')}" maxlength="40" placeholder="e.g. New car">`)}
    ${field('Amount €', num('p0amount', p0.amount, 'min="0" step="500"'))}${field('In months', num('p0months', p0.inMonths, 'min="0" max="60"'))}</div></fieldset>
  <p class="form-error" id="formError" role="alert" hidden></p>
  <div class="form-actions"><button class="button" type="submit">${formMode === 'edit' ? 'Save changes →' : 'Create my profile →'}</button>
  ${formMode === 'edit' ? '<button class="button secondary" type="button" data-studio="delete">Delete this profile</button>' : ''}
  <small>Synthetic demo data stays on this computer. Nothing is sent to a bank.</small></div></form>`;
}
function readForm(f) {
  const v = n => f.elements[n]?.value?.trim() ?? '', n = name => v(name) === '' ? null : Number(v(name));
  const spending = {};
  CATEGORIES.forEach(([k]) => { const x = n('sp_' + k); if (x) spending[k] = x; });
  const goals = [];
  [0, 1].forEach(i => { const t = v(`g${i}type`); if (t) goals.push({type: t, target: n(`g${i}target`), years: n(`g${i}years`), priority: goals.length + 1}); });
  const subscriptions = [0, 1, 2, 3, 4].map(i => ({name: v(`s${i}name`), monthly: n(`s${i}monthly`) ?? 0, lastUsedDays: n(`s${i}days`) ?? 0})).filter(s => s.name);
  const plannedPurchases = v('p0label') ? [{label: v('p0label'), amount: n('p0amount') ?? 0, inMonths: n('p0months') ?? 6}] : [];
  return {name: v('name'), age: n('age'), lifeStage: v('lifeStage'), purpose: v('purpose'), situation: v('situation'),
    riskTolerance: v('riskTolerance'), monthlyIncome: n('monthlyIncome'), incomeNote: v('incomeNote') || null, spending,
    cashSavings: n('cashSavings') ?? 0, investments: n('investments') ?? 0, companyShares: n('companyShares') ?? 0,
    monthlySavingCash: n('monthlySavingCash'), monthlySavingInvested: n('monthlySavingInvested') ?? 0,
    crashReaction: f.querySelector('[name=crashReaction]:checked')?.value || 'hold',
    disabilityCover: f.elements.disabilityCover.checked, will: f.elements.will.checked,
    confidence: n('confidence'), knowledge: n('knowledge'), shockAbsorb: n('shockAbsorb'), horizonYears: n('horizonYears'),
    goals, subscriptions, plannedPurchases};
}
function updateTotals() {
  const f = $('profileForm');
  if (!f) return;
  const r = readForm(f), spend = Object.values(r.spending).reduce((a, b) => a + b, 0);
  $('spendTotal').textContent = money(spend);
  const left = (r.monthlyIncome || 0) - spend - (r.monthlySavingCash || 0) - (r.monthlySavingInvested || 0);
  $('leftOver').textContent = left < 0 ? `Saving plus spending is ${money(-left)} more than your income: please check.`
    : `Left after spending and saving: ${money(left)} a month.`;
  $('leftOver').className = left < 0 ? 'sub warn' : 'sub';
}
function create() {
  formMode = 'create';
  const head = header('Create your own profile.', 'Six short steps, then Kairos builds your financial picture.', 'NEW PROFILE');
  const starts = `<div class="card start"><p class="eyebrow">START FROM</p><div class="start-row"><button class="button secondary" data-studio="blank">A blank profile</button>
    ${profiles.filter(p => !p.custom).map(p => `<button class="button secondary" data-studio="template" data-id="${esc(p.id)}">${esc(p.name)}’s example</button>`).join('')}</div>
    <p class="sub">An example fills the form with that customer’s numbers. Change anything before you create it.</p></div>`;
  return head + starts + profileForm(formState || BLANK);
}
function personalise() {
  const head = header('Make it yours.', 'Change your facts, habits or goals. Your picture updates with them.', 'PERSONALISE');
  if (!isCustom(customer)) {
    return head + `<div class="callout">${esc(workspace.tree.name)} is a demo customer and stays unchanged. Create your own copy to personalise it.</div>
      <button class="button" data-studio="copy">Copy ${esc(workspace.tree.name)} into a new profile →</button>`;
  }
  formMode = 'edit';
  if (formFor !== customer) {
    formFor = customer;
    formState = null;
    fetch(PROFILE_API + '/' + encodeURIComponent(customer)).then(r => r.json()).then(r => { formState = r; render(); });
    return head + '<div class="loading">Loading your profile…</div>';
  }
  return head + (formState ? profileForm(formState) : '<div class="loading">Loading your profile…</div>');
}
async function submitProfile(f) {
  const body = readForm(f), err = $('formError'), btn = f.querySelector('[type=submit]');
  err.hidden = true;
  btn.disabled = true;
  try {
    const edit = formMode === 'edit';
    const res = await fetch(PROFILE_API + (edit ? '/' + encodeURIComponent(customer) : ''), {method: edit ? 'PUT' : 'POST',
      headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
    const out = await res.json().catch(() => ({}));
    if (!res.ok) throw Error(out.error || `HTTP ${res.status}`);
    formState = body;
    formFor = out.id;
    await refreshCustomers();
    notify(edit ? 'Saved. Your picture is updating.' : `Welcome, ${out.name}. Your financial picture is being built.`);
    switchTo(out.id, 'overview');
  } catch (e) {
    err.textContent = 'Please check: ' + e.message;
    err.hidden = false;
    err.scrollIntoView({block: 'center'});
  } finally { btn.disabled = false; }
}
async function studioCommand(b) {
  const what = b.dataset.studio;
  if (what === 'rerun') {
    b.disabled = true;
    await fetch(API + encodeURIComponent(customer) + '/prediction/refresh', {method: 'POST'}).catch(() => {});
    notify('Running again.');
    load();
  }
  if (what === 'blank') { formState = JSON.parse(JSON.stringify(BLANK)); render(); }
  if (what === 'template' || what === 'copy') {
    const id = what === 'copy' ? customer : b.dataset.id;
    const r = await (await fetch(PROFILE_API + '/' + encodeURIComponent(id))).json();
    formState = {...r, name: ''};
    location.hash = 'create';
    render();
    notify(`Filled in with ${r.name}’s numbers. Add your name and change anything you like.`);
  }
  if (what === 'delete' && confirmDelete()) {
    await fetch(PROFILE_API + '/' + encodeURIComponent(customer), {method: 'DELETE'});
    formFor = null;
    await refreshCustomers();
    notify('Profile deleted.');
    switchTo('maya', 'overview');
  }
}
let deleteArmed = 0;
function confirmDelete() {
  if (Date.now() - deleteArmed < 5000) return true;
  deleteArmed = Date.now();
  notify('Press “Delete this profile” again within 5 seconds to delete it for good.');
  return false;
}
document.addEventListener('click', e => { const b = e.target.closest('[data-studio]'); if (b) { e.preventDefault(); studioCommand(b); } });
document.addEventListener('submit', e => { if (e.target.id === 'profileForm') { e.preventDefault(); submitProfile(e.target); } });
document.addEventListener('input', e => { if (e.target.closest('#profileForm')) updateTotals(); });
refreshCustomers();

/* Team view: the "behind the scenes" page with agents, models and checks is hidden from customers. */
(function teamView() {
  const on = (() => { try { return localStorage.getItem('kairos-team') === '1'; } catch (e) { return false; } })();
  const apply = v => {
    document.body.classList.toggle('team', v);
    const b = document.getElementById('teamToggle');
    if (b) b.textContent = 'Team view: ' + (v ? 'on' : 'off');
    if (!v && location.hash === '#agents') location.hash = 'overview';
  };
  apply(on);
  document.addEventListener('click', e => {
    if (e.target.id !== 'teamToggle') return;
    const v = !document.body.classList.contains('team');
    try { localStorage.setItem('kairos-team', v ? '1' : '0'); } catch (err) { /* private mode */ }
    apply(v);
  });
})();

/* Book a call: set BOOKING_URL to the Calendly link and the button opens it in a new tab. */
const BOOKING_URL = '';
document.addEventListener('click', e => {
  const b = e.target.closest('#bookCall');
  if (!b) return;
  if (BOOKING_URL) { b.href = BOOKING_URL; b.target = '_blank'; return; }
  e.preventDefault();
  notify('Booking is coming soon. Your advisor will be able to pick a time with you here.');
});
