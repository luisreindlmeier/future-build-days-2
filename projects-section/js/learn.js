'use strict';
/* Learn & grow: a learning path of two-minute missions (learn one idea, try it on your own numbers, answer one
   question with instant feedback), a weekly challenge from your weakest spending area, a first-visit tour of the
   tree, and rewards that show on the tree (a flower per finished mission). Progress is kept in this browser.
   Uses dashboard.js (workspace, customer, render, notify, esc, $) and charts.js (C, k). */
const LS = {
  get(key, fallback) { try { return JSON.parse(localStorage.getItem('kairos-' + key)) ?? fallback; } catch (e) { return fallback; } },
  set(key, v) { try { localStorage.setItem('kairos-' + key, JSON.stringify(v)); } catch (e) { /* private mode */ } },
};
function learned() {
  const out = {...LS.get('learn-' + customer, {})};
  (workspace?.learning || []).forEach(e => { out[e.missionId] = {at: e.at, right: e.correct}; });
  return out;
}
function learnedCount() { return Object.keys(learned()).length; }
const fmtE = v => '€' + Math.round(v).toLocaleString('en');

/* ------------------------------------------------------------------ facts from the customer's own data */
function facts() {
  const a = workspace.assessment || {}, t = workspace.tree || {};
  const safety = (t.roots || []).find(r => r.category === 'EMERGENCY') || {balance: 0, target: 0};
  const worst = [...(t.leaves || [])].filter(l => !l.essential && l.peerAverage > 0)
    .sort((x, y) => y.monthlyAmount / y.peerAverage - x.monthlyAmount / x.peerAverage)[0];
  const intake = workspace.prediction?.intake || {}, prot = (t.roots || []).find(r => r.category === 'PROTECTION');
  return {sold: intake.crash_reaction === 'sell', covered: !!intake.disability_cover || !!(prot && prot.balance > 0), spend: a.monthlySpend || 2000, buffer: safety.balance || 0, bufferTarget: safety.target || 3 * (a.monthlySpend || 2000),
    bufferMonths: a.bufferMonths || 0, oneShare: a.largestPositionShare || 0, savingsRate: a.savingsRate || 0, worst};
}

/* ------------------------------------------------------------------ the missions */
const MISSIONS = [
  {id: 'safety', icon: '🛟', title: 'Your safety net', topic: 'Saving', need: f => f.bufferMonths < 3,
    learn: f => `A safety net is money you can reach quickly when life surprises you: a broken boiler, a gap between jobs. A common aim is <b>3 months of spending</b>. You have about <b>${f.bufferMonths.toFixed(1)} months</b> today.`,
    try: 'buffer',
    quiz: {q: 'Where should your safety net live?', a: ['In shares, so it can grow', 'In an easy-access savings account', 'Spread across your credit cards'], ok: 1,
      why: 'It has to be there when you need it, at full value. Shares can be down exactly when the boiler breaks.'}},
  {id: 'spending', icon: '🍃', title: 'Spending like people like you', topic: 'Spending', need: f => !!f.worst && f.worst.monthlyAmount > 1.2 * f.worst.peerAverage,
    learn: f => f.worst ? `You spend <b>${fmtE(f.worst.monthlyAmount)}</b> a month on ${esc(f.worst.label.toLowerCase())}. Households with your income spend about <b>${fmtE(f.worst.peerAverage)}</b>. Small, steady cuts add up more than big one-off ones.`
      : 'Comparing your spending with households like yours shows where small changes go furthest.',
    try: 'cut',
    quiz: {q: 'You cut €100 a month and save it. Ignoring interest, how much is that after 5 years?', a: ['€500', '€1,200', '€6,000'], ok: 2,
      why: '€100 × 12 months × 5 years = €6,000. Monthly amounts feel small; yearly they don’t.'}},
  {id: 'compound', icon: '🌱', title: 'How money grows', topic: 'Investing', need: f => f.savingsRate < .15,
    learn: () => 'Money that is invested can earn returns, and those returns can earn returns too. That is <b>compounding</b>. Time matters more than the amount you start with.',
    try: 'compound',
    quiz: {q: 'You invest €100 at 2% a year for 5 years and leave it. You end with…', a: ['Exactly €102', 'More than €110', 'Less than €102'], ok: 1,
      why: 'Each year’s 2% is earned on a slightly bigger amount, so after 5 years it is about €110.41.'}},
  {id: 'spread', icon: '🧺', title: 'Don’t put all eggs in one basket', topic: 'Investing', need: f => f.oneShare > .3,
    learn: f => `If one company holds most of your money, one bad year there hits all of it. Today about <b>${Math.round(f.oneShare * 100)}%</b> of your investments sit in one place.`,
    try: 'spread',
    quiz: {q: 'Which is usually less risky?', a: ['Shares of one company', 'A fund that holds hundreds of companies', 'They carry the same risk'], ok: 1,
      why: 'In a broad fund, one company’s bad year is a small part of the whole.'}},
  {id: 'calm', icon: '⛈', title: 'Staying calm in a storm', topic: 'Investing', need: f => f.sold,
    learn: () => 'Markets fall sometimes, often sharply. People who sell in a panic lock in the loss and often miss the recovery. A simple written rule helps you stay calm.',
    try: 'storm',
    quiz: {q: 'Markets fall 30% in a month. What usually protects long-term investors best?', a: ['Selling everything until it feels safe', 'Following the plan they wrote down in calm times', 'Moving everything into one strong company'], ok: 1,
      why: 'A plan made in calm times keeps decisions steady when emotions run high.'}},
  {id: 'protect', icon: '☂', title: 'Protecting your income', topic: 'Protection', need: f => !f.covered,
    learn: f => `Your income pays for everything else. Without it, your safety net covers about <b>${f.bufferMonths.toFixed(1)} months</b>. Income protection pays part of your income if illness or an accident stops you working.`,
    try: 'protect',
    quiz: {q: 'What does income-protection cover replace?', a: ['Part of your income if you cannot work', 'Your savings if markets fall', 'The cost of a holiday you cancel'], ok: 0,
      why: 'It pays a share of your income, often around 60%, while you cannot work.'}},
];
/* one small animated scene per mission (SVG + CSS; still for reduced motion) */
const ILLUS = {
  safety: f => { const lvl = Math.max(.06, Math.min(1, f.bufferMonths / 3)); return `<svg viewBox="0 0 220 130"><rect x="70" y="14" width="80" height="100" rx="12" fill="#eef3fa" stroke="#9fb1ff" stroke-width="3"/>
    <rect class="il-fill" x="73" y="${(111 - 94 * lvl).toFixed(0)}" width="74" height="${(94 * lvl).toFixed(0)}" rx="9" fill="#16745e" opacity=".8" style="--h:${(94 * lvl).toFixed(0)}px"/>
    <line x1="62" x2="158" y1="17" y2="17" stroke="#0018a8" stroke-dasharray="4 4"/><text x="166" y="21" font-size="11" fill="#0018a8">3 months</text>
    <text x="110" y="128" font-size="11" text-anchor="middle" fill="#5c6b7e">you: ${f.bufferMonths.toFixed(1)} months</text><circle class="il-drop" cx="110" cy="0" r="5" fill="#16745e"/></svg>`; },
  spending: () => `<svg viewBox="0 0 220 130"><g class="il-sway"><ellipse cx="60" cy="40" rx="34" ry="24" fill="#b7603a"/><ellipse cx="80" cy="34" rx="22" ry="16" fill="#d08458"/></g>
    ${[0, 1, 2].map(i => `<circle class="il-coin" style="animation-delay:${i * .7}s" cx="${70 + i * 12}" cy="60" r="8" fill="#e3c35c" stroke="#b08a2a" stroke-width="2"/>`).join('')}
    <path d="M140 88 q30 -26 60 0 v24 q-30 14 -60 0z" fill="#f2bfd0"/><rect x="164" y="78" width="14" height="5" rx="2" fill="#5c6b7e"/><circle cx="188" cy="94" r="2.4" fill="#152a46"/></svg>`,
  compound: () => `<svg viewBox="0 0 220 130"><rect x="20" y="112" width="180" height="6" rx="3" fill="#8a6a43"/>
    <g class="il-grow"><path d="M110 112 v-56" stroke="#6b5440" stroke-width="6" stroke-linecap="round"/><circle cx="110" cy="48" r="26" fill="#2f8a5f"/><circle cx="92" cy="58" r="16" fill="#3da06f"/><circle cx="128" cy="58" r="16" fill="#3da06f"/><circle cx="102" cy="40" r="7" fill="#6cc393"/></g>
    ${[0, 1, 2, 3].map(i => `<text class="il-plus" style="animation-delay:${i * .6}s" x="${80 + i * 20}" y="30" font-size="13" fill="#16745e" font-weight="700">+€</text>`).join('')}</svg>`,
  spread: () => `<svg viewBox="0 0 220 130"><g class="il-tip"><path d="M18 78 h66 l-8 34 h-50z" fill="#c9a46a"/>${[0, 1, 2].map(i => `<ellipse cx="${36 + i * 15}" cy="72" rx="7" ry="9" fill="#fff6e5" stroke="#d9c9a6"/>`).join('')}</g>
    ${[0, 1, 2, 3].map(i => `<g><path d="M${118 + i * 24} 96 h20 l-3 14 h-14z" fill="#c9a46a"/><ellipse cx="${128 + i * 24}" cy="90" rx="6" ry="8" fill="#fff6e5" stroke="#d9c9a6"/></g>`).join('')}
    <text x="52" y="126" font-size="11" text-anchor="middle" fill="#b3412e">one basket</text><text x="164" y="126" font-size="11" text-anchor="middle" fill="#16745e">many baskets</text></svg>`,
  calm: () => `<svg viewBox="0 0 220 130"><g class="il-cloud"><ellipse cx="60" cy="26" rx="30" ry="14" fill="#9aa7ba"/><ellipse cx="80" cy="20" rx="20" ry="12" fill="#b6c0cf"/><path d="M58 40 l-6 12 h8 l-6 12" stroke="#e3c35c" stroke-width="3" fill="none"/></g>
    <path class="il-line" d="M14 70 L60 66 L90 104 L120 96 L150 72 L180 58 L206 50" fill="none" stroke="#0018a8" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>
    <text x="96" y="122" font-size="11" fill="#5c6b7e">fall</text><text x="170" y="46" font-size="11" fill="#16745e">recovery</text></svg>`,
  protect: () => `<svg viewBox="0 0 220 130">${[0, 1, 2, 3, 4, 5].map(i => `<line class="il-rain" style="animation-delay:${i * .25}s" x1="${40 + i * 28}" y1="0" x2="${36 + i * 28}" y2="12" stroke="#9fb1ff" stroke-width="2" stroke-linecap="round"/>`).join('')}
    <path d="M60 64 q50 -46 100 0 q-12 -8 -25 0 q-12 -8 -25 0 q-12 -8 -25 0 q-12 -8 -25 0z" fill="#0018a8"/><path d="M110 64 v34 q0 8 -8 8" stroke="#152a46" stroke-width="3" fill="none"/>
    <rect x="86" y="96" width="48" height="26" fill="#eef3fa" stroke="#9aa7ba"/><path d="M80 98 l30 -18 l30 18" fill="#dbe3f0" stroke="#9aa7ba"/><text x="110" y="114" font-size="10" text-anchor="middle" fill="#152a46">income</text></svg>`,
};

/* order: what this customer needs first, then the rest */
function orderedMissions() { const f = facts(); return [...MISSIONS].sort((a, b) => (b.need(f) ? 1 : 0) - (a.need(f) ? 1 : 0)); }

/* ------------------------------------------------------------------ "try it" widgets on the customer's numbers */
function widget(kind) {
  const f = facts();
  const slider = (id, min, max, step, val, label) => `<label class="lw-slider"><span>${label}</span><input type="range" id="${id}" min="${min}" max="${max}" step="${step}" value="${val}"><b id="${id}V"></b></label>`;
  return {
    buffer: `${slider('lwA', 25, 1000, 25, 200, 'I put aside each month')}<div class="lw-out" id="lwOut"></div>`,
    cut: `${slider('lwA', 10, Math.max(50, Math.round((f.worst?.monthlyAmount || 300) * .6 / 10) * 10), 10, 60, 'I spend less each month')}<div class="lw-out" id="lwOut"></div>`,
    compound: `${slider('lwA', 25, 1000, 25, 150, 'I invest each month')}${slider('lwB', 1, 40, 1, 15, 'for this many years')}<div class="lw-out" id="lwOut"></div>`,
    spread: `<div class="lw-toggle"><button type="button" class="on" data-lw="one">One company</button><button type="button" data-lw="many">A fund of 100 companies</button></div><div class="lw-out" id="lwOut"></div>`,
    storm: `<div class="lw-toggle"><button type="button" class="on" data-lw="hold">Hold and follow my plan</button><button type="button" data-lw="sell">Sell after the fall</button></div><div class="lw-out" id="lwOut"></div>`,
    protect: `${slider('lwA', 1, 12, 1, 6, 'Months without income')}<div class="lw-out" id="lwOut"></div>`,
  }[kind];
}
function updateWidget(kind) {
  const f = facts(), out = document.getElementById('lwOut');
  if (!out) return;
  const v = id => +(document.getElementById(id)?.value || 0);
  const show = (id, s) => { const el = document.getElementById(id + 'V'); if (el) el.textContent = s; };
  const meter = (pct, col = C.blue) => `<div class="lw-meter"><i style="width:${Math.max(2, Math.min(100, pct))}%;background:${col}"></i></div>`;
  if (kind === 'buffer') {
    const m = v('lwA'); show('lwA', fmtE(m));
    const target = 3 * f.spend, need = Math.max(0, target - f.buffer), months = Math.ceil(need / m);
    out.innerHTML = need <= 0 ? '<p>You already have 3 months of spending set aside. 🎉</p>'
      : `<p>Your safety net reaches <b>3 months</b> (${fmtE(target)}) in about <b>${months} month${months > 1 ? 's' : ''}</b>.</p>${meter(f.buffer / target * 100, C.ok)}<small>Today: ${fmtE(f.buffer)} of ${fmtE(target)}</small>`;
  } else if (kind === 'cut') {
    const m = v('lwA'); show('lwA', fmtE(m));
    const fv = (pm, r, y) => { const i = r / 12; let s = 0; for (let n = 0; n < y * 12; n++) s = s * (1 + i) + pm; return s; };
    out.innerHTML = `<div class="lw-cols"><div><span>In a year</span><b>${fmtE(m * 12)}</b></div><div><span>Saved for 10 years</span><b>${fmtE(m * 120)}</b></div><div><span>Invested for 10 years*</span><b>${fmtE(fv(m, .05, 10))}</b></div></div><small>*Example at 5% a year. Returns are not guaranteed.</small>`;
  } else if (kind === 'compound') {
    const m = v('lwA'), y = v('lwB'); show('lwA', fmtE(m)); show('lwB', y + ' yrs');
    const i = .05 / 12; let s = 0; for (let n = 0; n < y * 12; n++) s = s * (1 + i) + m;
    const paid = m * 12 * y;
    out.innerHTML = `<p>You put in <b>${fmtE(paid)}</b>. At 5% a year it could become <b>${fmtE(s)}</b>.</p>
      <div class="lw-stack"><i style="width:${paid / s * 100}%;background:${C.base}">your money</i><i style="width:${(s - paid) / s * 100}%;background:${C.ok}">growth</i></div><small>Example only. Real returns go up and down.</small>`;
  } else if (kind === 'spread') {
    const many = document.querySelector('[data-lw="many"]')?.classList.contains('on');
    const hit = many ? 40 / 100 : 40;
    out.innerHTML = `<p>One company falls <b>40%</b>. Your investments fall by <b>${many ? '0.4%' : '40%'}</b>.</p>${meter(100 - hit, many ? C.ok : C.bad)}<small>${many ? 'The other 99 companies carry on.' : 'Everything depended on that one company.'}</small>`;
  } else if (kind === 'storm') {
    const sell = document.querySelector('[data-lw="sell"]')?.classList.contains('on');
    out.innerHTML = `<p>€10,000 invested. Markets fall 30%, then recover over two years.</p><div class="lw-cols"><div><span>After the fall</span><b>€7,000</b></div><div><span>Two years later</span><b style="color:${sell ? C.bad : C.ok}">${sell ? '€7,200' : '€10,500'}</b></div></div><small>${sell ? 'Selling locked in the loss; the cash missed the recovery.' : 'Holding meant you were there for the recovery.'} Example figures.</small>`;
  } else if (kind === 'protect') {
    const m = v('lwA'); show('lwA', m + ' months');
    const lasts = f.spend > 0 ? f.buffer / f.spend : 0, gap = Math.max(0, m * f.spend - f.buffer);
    out.innerHTML = `<p>Your safety net lasts about <b>${lasts.toFixed(1)} months</b>. Without cover, the gap for ${m} months is <b>${fmtE(gap)}</b>.</p>${meter(Math.min(100, lasts / m * 100), lasts >= m ? C.ok : C.watch)}`;
  }
}

/* ------------------------------------------------------------------ learn page: the path */
function learnPage() {
  const done = learned(), list = orderedMissions(), f = facts(), streak = learnStreak();
  const next = list.find(m => !done[m.id]);
  const nodes = list.map((m, i) => {
    const state = done[m.id] ? 'done' : m === next ? 'next' : 'open';
    return `<li class="lp-node ${state} ${i % 2 ? 'right' : 'left'}"><button type="button" data-mission="${m.id}" aria-label="${esc(m.title)}${done[m.id] ? ', finished' : ''}">
      <span class="lp-bubble">${done[m.id] ? '✓' : m.icon}</span><span class="lp-text"><b>${esc(m.title)}</b><small>${m.topic} · 2 min${m.need(f) && !done[m.id] ? ' · <em>for you</em>' : ''}</small></span></button></li>`;
  }).join('');
  const n = Object.keys(done).length;
  return header('Grow your money confidence.', 'Two-minute missions. Learn one idea, try it on your own numbers, check yourself.', 'LEARN & GROW') + `
    <div class="lp-top card"><div class="lp-ring" style="--p:${n / MISSIONS.length * 100}"><b>${n}/${MISSIONS.length}</b><span>missions</span></div>
      <div><h2>${next ? `Next: ${esc(next.title)}` : 'You finished every mission. 🎉'}</h2><p class="sub">Every finished mission plants a flower on your tree.${streak ? ` 🔥 ${streak}-day learning streak.` : ''}</p>
      ${next ? `<button type="button" class="button" data-mission="${next.id}">Start · 2 min →</button>` : ''}</div></div>
    <ol class="lp-path">${nodes}</ol>`;
}

function learnStreak() {
  const days = LS.get('learn-days-' + customer, []);
  let s = 0;
  for (let d = new Date(); ; d.setDate(d.getDate() - 1)) { if (days.includes(d.toISOString().slice(0, 10))) s++; else break; }
  return s;
}

/* ------------------------------------------------------------------ mission player */
let MP = null;
function openMission(id) {
  const m = MISSIONS.find(x => x.id === id);
  if (!m) return;
  MP = {m, step: 0, picked: null};
  drawMission();
  $('detail').showModal();
}
function drawMission() {
  const {m, step} = MP, f = facts();
  const dots = [0, 1, 2].map(i => `<i class="${i < step ? 'done' : i === step ? 'now' : ''}"></i>`).join('');
  let body = '';
  if (step === 0) body = `<p class="eyebrow">LEARN</p><h2>${m.icon} ${esc(m.title)}</h2><div class="mp-illus">${(ILLUS[m.id] || (() => ''))(f)}</div><p class="mp-text">${m.learn(f)}</p><button type="button" class="button" data-mp="next">Try it on my numbers →</button>`;
  if (step === 3) {
    const right = MP.picked === m.quiz.ok, n = learnedCount();
    body = `<div class="mp-done"><svg viewBox="0 0 120 120" class="mp-flower"><path class="st" d="M60 112 V58" stroke="#4f8a4a" stroke-width="5" stroke-linecap="round"/><ellipse class="lf" cx="72" cy="86" rx="12" ry="6" fill="#3da06f" transform="rotate(-30 72 86)"/>
      ${[0, 72, 144, 216, 288].map((d, i) => `<ellipse class="pt" style="animation-delay:${.5 + i * .08}s" cx="${(60 + Math.cos(d / 57.3) * 14).toFixed(1)}" cy="${(46 + Math.sin(d / 57.3) * 14).toFixed(1)}" rx="11" ry="8" transform="rotate(${d} ${(60 + Math.cos(d / 57.3) * 14).toFixed(1)} ${(46 + Math.sin(d / 57.3) * 14).toFixed(1)})" fill="#f2bfd0"/>`).join('')}<circle class="pt" style="animation-delay:.95s" cx="60" cy="46" r="8" fill="#f0b429"/></svg>
      <p class="eyebrow">MISSION COMPLETE</p><h2>${esc(m.title)}</h2><p class="sub">${right ? 'You got the question right.' : 'Good to know now, not later.'} A new flower grows on your tree. You have finished ${n} of ${MISSIONS.length} missions.</p>
      <button type="button" class="button" data-mp="close">See my tree 🌳</button><button type="button" class="link" data-mp="path">Back to my learning path</button></div>`;
  }
  if (step === 1) body = `<p class="eyebrow">TRY IT</p><h2>Move it and watch</h2><div class="mp-widget">${widget(m.try)}</div><button type="button" class="button" data-mp="next">One quick question →</button>`;
  if (step === 2) {
    const q = m.quiz, picked = MP.picked;
    body = `<p class="eyebrow">CHECK YOURSELF</p><h2>${esc(q.q)}</h2><div class="mp-answers">${q.a.map((a, i) => `<button type="button" data-mp-a="${i}" class="${picked == null ? '' : i === q.ok ? 'right' : i === picked ? 'wrong' : 'dim'}" ${picked != null ? 'disabled' : ''}>${esc(a)}</button>`).join('')}</div>
      ${picked == null ? '' : `<div class="mp-why ${picked === q.ok ? 'ok' : 'no'}"><b>${picked === q.ok ? 'Exactly right.' : 'Not quite.'}</b> ${esc(q.why)}</div><button type="button" class="button" data-mp="finish">${picked === q.ok ? 'Plant my flower 🌸' : 'Got it, finish'}</button>`}`;
  }
  $('detail-content').innerHTML = `<div class="mp step${step}">${step < 3 ? `<div class="mp-dots">${dots}</div>` : ''}<div class="mp-body">${body}</div></div>`;
  if (step === 1) updateWidget(m.try);
}
async function finishMission() {
  const {m} = MP, right = MP.picked === m.quiz.ok, local = LS.get('learn-' + customer, {});
  local[m.id] = {at: Date.now(), right};
  LS.set('learn-' + customer, local);                              // offline fallback
  const days = LS.get('learn-days-' + customer, []), today = new Date().toISOString().slice(0, 10);
  if (!days.includes(today)) LS.set('learn-days-' + customer, [...days, today].slice(-60));
  try {                                                             // saved for the advisor view
    const r = await fetch(API + encodeURIComponent(customer) + '/learning', {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({missionId: m.id, title: m.title, topic: m.topic, correct: right})});
    if (r.ok && workspace) workspace.learning = await r.json();
  } catch (e) { /* kept locally */ }
  MP.step = 3;
  drawMission();
  celebrate();
}

/* ------------------------------------------------------------------ weekly challenge (overview) */
function weekKey() { const d = new Date(), j = new Date(d.getFullYear(), 0, 1); return d.getFullYear() + '-w' + Math.ceil(((d - j) / 864e5 + j.getDay() + 1) / 7); }
function challengeCard() {
  const f = facts();
  if (!f.worst) return '';
  const weekly = Math.round(f.worst.peerAverage * 1.1 / 4.33 / 5) * 5;
  const key = 'challenge-' + customer + '-' + weekKey(), ticks = LS.get(key, []);
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const done = ticks.length >= 7;
  return `<section class="card challenge"><div><p class="eyebrow">THIS WEEK’S CHALLENGE</p><h2>Keep ${esc(f.worst.label.toLowerCase())} under ${fmtE(weekly)} this week</h2>
      <p class="sub">Tap each day you stayed on track. People like you spend about ${fmtE(f.worst.peerAverage)} a month on it.</p></div>
    <div class="ch-days">${days.map((d, i) => `<button type="button" data-tick="${i}" class="${ticks.includes(i) ? 'on' : ''}" aria-pressed="${ticks.includes(i)}"><span>${ticks.includes(i) ? '✓' : ''}</span>${d}</button>`).join('')}</div>
    <div class="ch-foot">${done ? '<b>🏆 Challenge complete. Your boughs thank you.</b>' : `<b>${ticks.length}/7</b> days`}</div></section>`;
}

/* ------------------------------------------------------------------ first-visit tour of the tree */
const TOUR = [
  {sel: '.t3-stage', title: 'This is your wealth tree', text: 'Leaves are your spending, the trunk your investing, the roots your savings. Healthy money, healthy tree.'},
  {sel: '.t3-chips', title: 'Tap any part', text: 'Pick a bough or a chip to see what it means for you and one thing to do about it. Drag the tree to turn it.'},
  {sel: 'nav a[href="#learn"]', title: 'Help it grow', text: 'Two-minute missions plant flowers on your tree and build your money confidence.'},
];
let tourStep = -1;
function maybeTour() {
  if (location.hash && location.hash !== '#overview') return;
  if (LS.get('toured', false) || tourStep >= 0 || !document.querySelector('.t3-stage')) return;
  tourStep = 0;
  setTimeout(drawTour, 600);
}
function drawTour() {
  document.querySelector('.tour')?.remove();
  const s = TOUR[tourStep], el = s && document.querySelector(s.sel);
  if (!s || !el) { LS.set('toured', true); tourStep = -1; return; }
  el.scrollIntoView({block: 'center', behavior: reducedMotion() ? 'auto' : 'smooth'});
  setTimeout(() => {
    const r = el.getBoundingClientRect(), box = document.createElement('div');
    box.className = 'tour';
    const sx = scrollX, sy = scrollY, below = r.bottom + 14 + 170 <= innerHeight;   // page coordinates: stays put on scroll
    box.innerHTML = `<div class="tour-ring" style="left:${r.left + sx - 6}px;top:${r.top + sy - 6}px;width:${r.width + 12}px;height:${r.height + 12}px"></div>
      <div class="tour-card" role="dialog" aria-label="${esc(s.title)}" style="left:${Math.min(innerWidth - 340, Math.max(16, r.left)) + sx}px;top:${(below ? r.bottom + 14 : Math.max(16, r.top - 180)) + sy}px">
      <b>${esc(s.title)}</b><p>${esc(s.text)}</p><div><span>${tourStep + 1} of ${TOUR.length}</span><button type="button" data-tour="skip" class="link">Skip</button><button type="button" data-tour="next" class="button">${tourStep === TOUR.length - 1 ? 'Got it' : 'Next →'}</button></div></div>`;
    document.body.appendChild(box);
    box.querySelector('[data-tour="next"]').focus();
  }, 350);
}

/* ------------------------------------------------------------------ celebration */
function celebrate() {
  if (reducedMotion()) return;
  const c = document.createElement('div');
  c.className = 'confetti';
  const cols = ['#0018a8', '#16745e', '#4a63d9', '#f2bfd0', '#e3cd6a'];
  c.innerHTML = Array.from({length: 40}, (_, i) => `<i style="left:${Math.random() * 100}%;background:${cols[i % cols.length]};animation-delay:${Math.random() * .4}s;transform:rotate(${Math.random() * 360}deg)"></i>`).join('');
  document.body.appendChild(c);
  setTimeout(() => c.remove(), 2200);
}

/* ------------------------------------------------------------------ events */
document.addEventListener('click', e => {
  const t = e.target;
  const mission = t.closest('[data-mission]');
  if (mission) { openMission(mission.dataset.mission); return; }
  const mp = t.closest('[data-mp]');
  if (mp && MP) {
    if (mp.dataset.mp === 'next') { MP.step++; drawMission(); }
    if (mp.dataset.mp === 'finish') finishMission();
    if (mp.dataset.mp === 'close' || mp.dataset.mp === 'path') {
      $('detail').close();
      const to = mp.dataset.mp === 'close' ? 'overview' : 'learn';
      MP = null;
      if (location.hash !== '#' + to) location.hash = to; else render();
    }
    return;
  }
  const ans = t.closest('[data-mp-a]');
  if (ans && MP && MP.picked == null) { MP.picked = +ans.dataset.mpA; drawMission(); return; }
  const tog = t.closest('[data-lw]');
  if (tog) { tog.parentElement.querySelectorAll('button').forEach(b => b.classList.toggle('on', b === tog)); updateWidget(MP.m.try); return; }
  const tick = t.closest('[data-tick]');
  if (tick) {
    const key = 'challenge-' + customer + '-' + weekKey(), ticks = LS.get(key, []), d = +tick.dataset.tick;
    const nextTicks = ticks.includes(d) ? ticks.filter(x => x !== d) : [...ticks, d];
    LS.set(key, nextTicks);
    if (nextTicks.length === 7 && ticks.length === 6) celebrate();
    render();
    return;
  }
  const tour = t.closest('[data-tour]');
  if (tour) {
    if (tour.dataset.tour === 'skip' || tourStep >= TOUR.length - 1) { document.querySelector('.tour')?.remove(); LS.set('toured', true); tourStep = -1; return; }
    tourStep++;
    drawTour();
  }
});
document.addEventListener('input', e => { if (e.target.closest('.mp-widget') && MP) updateWidget(MP.m.try); });

/* deep link for demos: ?mission=compound&step=1 opens a mission at a step (0 learn, 1 try, 2 question) */
function maybeOpenMission() {
  const q = new URLSearchParams(location.search), id = q.get('mission');
  if (!id || MP || location.hash !== '#learn' || !MISSIONS.some(m => m.id === id)) return;
  openMission(id);
  MP.step = Math.max(0, Math.min(3, +(q.get('step') || 0)));
  if (MP.step === 3) MP.picked = MP.m.quiz.ok;
  drawMission();
}

/* ------------------------------------------------------------------ advisor view: what the customer learned */
function advisorLearning() {
  const list = [...(workspace?.learning || [])].sort((a, b) => b.at - a.at), name = esc(workspace.tree.name);
  const open = MISSIONS.filter(m => !list.some(e => e.missionId === m.id) && m.need(facts()));
  const wrong = list.filter(e => !e.correct);
  return `<section class="card adv-learn" style="margin-top:22px"><div class="card-head"><div><p class="eyebrow">LEARNING</p><h2>What ${name} has learned</h2></div>
      <div class="lp-ring small" style="--p:${list.length / MISSIONS.length * 100}"><b>${list.length}/${MISSIONS.length}</b></div></div>
    ${list.length ? `<ul class="adv-list">${list.map(e => `<li><span class="${e.correct ? 'ok' : 'no'}">${e.correct ? '✓' : '?'}</span><b>${esc(e.title)}</b><small>${esc(e.topic)} · ${new Date(e.at).toLocaleDateString('en-GB', {day: 'numeric', month: 'short'})}${e.correct ? '' : ' · quiz answer was wrong'}</small></li>`).join('')}</ul>`
      : `<p class="sub">No missions finished yet.</p>`}
    ${wrong.length || open.length ? `<p class="eyebrow" style="margin-top:18px">TALKING POINTS</p><ul class="list">${wrong.map(e => `<li>Revisit <b>${esc(e.title.toLowerCase())}</b> together: the quiz answer was wrong.</li>`).join('')}${open.slice(0, 2).map(m => `<li>Suggest <b>${esc(m.title.toLowerCase())}</b>: it fits ${name}’s numbers.</li>`).join('')}</ul>` : ''}</section>`;
}
