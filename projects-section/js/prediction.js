'use strict';
/* My prediction: a short "working on it" sequence tied to the real calculation, then one interactive chart.
   Hover or drag along the chart to read any age; pick a change to see what it does to your goal.
   Uses dashboard.js (workspace, customer, render, load, notify, esc, API) and charts.js (C, k, pctNum, mainGoal). */
const PRED = {played: {}, playing: null, sel: null, hover: null, timer: 0};
const PRED_STEPS = ['Reading your accounts', 'Simulating 2,000 possible futures', 'Testing your choices', 'Checking every number'];
const PRED_SHORT = {baseline: 'Same habits', full_plan: 'All changes', spend_less: 'Spend less', buffer: 'Build a buffer', invest: 'Invest monthly',
  hold_rule: 'Hold in a crash', diversify: 'Diversify', cover: 'Disability cover', close_gap: 'Close spending gap'};

function parseEur(s) {                       // "€2.90m" / "€294k" / "€8,256" -> number
  const m = /€\s?([\d.,]+)\s?([km])?/i.exec(String(s || ''));
  if (!m) return 0;
  return parseFloat(m[1].replace(/,/g, '')) * ({k: 1e3, m: 1e6}[(m[2] || '').toLowerCase()] || 1);
}

function predictionPage() {
  const p = workspace.prediction || {};
  const head = header('What your money could do.', 'Thousands of possible futures, built from your own numbers.', 'MY PREDICTION');
  const playing = PRED.playing && PRED.playing.customer === customer;
  if (!PRED.played[customer] && p.status === 'READY' && !playing) startPlaying(false);
  if (p.status === 'RUNNING' || (PRED.playing && PRED.playing.customer === customer)) return head + loader(p.status);
  if (p.status !== 'READY' || !p.engine) return head + `<div class="card empty"><h2>Your prediction is not available right now.</h2><button class="button secondary" data-pred="refresh">Try again</button></div>`;
  return head + result();
}

function startPlaying(refresh) {
  PRED.playing = {customer, start: performance.now(), refresh};
  clearInterval(PRED.timer);
  PRED.timer = setInterval(() => {
    const p = workspace?.prediction || {};
    const done = performance.now() - PRED.playing.start > 2800 && p.status === 'READY';
    if (done) { clearInterval(PRED.timer); PRED.played[customer] = true; PRED.playing = null; }
    if (location.hash === '#future') render();
  }, 450);
}

function loader(status) {
  const t = PRED.playing ? performance.now() - PRED.playing.start : 0;
  const ready = status === 'READY';
  const at = Math.min(PRED_STEPS.length - (ready ? 0 : 1), Math.floor(t / 700));     // the last step waits for the real result
  return `<section class="card pred-loader"><div class="pred-orb"><span></span><span></span><span></span></div>
    <h2>Building your prediction…</h2><ol class="pred-steps">${PRED_STEPS.map((s, i) => `<li class="${i < at ? 'done' : i === at ? 'now' : ''}"><i>${i < at ? '✓' : ''}</i>${s}</li>`).join('')}</ol>
    <div class="pred-progress"><i style="width:${Math.min(100, (at + (ready ? 0 : .5)) / PRED_STEPS.length * 100)}%"></i></div></section>`;
}

function result() {
  const p = workspace.prediction, e = p.engine, f = p.prediction?.output || {}, g0 = mainGoal(e);
  const sc = e.scenarios || [];
  if (!PRED.sel || !sc.some(s => s.id === PRED.sel)) PRED.sel = (sc.find(s => s.kind === 'combo') || sc.find(s => s.kind === 'change') || sc[0]).id;
  const base = sc.find(s => s.kind === 'baseline'), pick = sc.find(s => s.id === PRED.sel);
  const b = pctNum(base.results.goal_success[g0.id]), v = pctNum(pick.results.goal_success[g0.id]), diff = v - b;
  const best = sc.find(s => s.id === f.best_change?.scenario_id);
  const chips = sc.map(s => `<button type="button" class="pred-chip${s.id === PRED.sel ? ' on' : ''}${s.kind === 'baseline' ? ' base' : ''}" data-pred-sel="${esc(s.id)}">${esc(PRED_SHORT[s.id] || s.label)}<b>${esc(s.results.goal_success[g0.id])}</b></button>`).join('');
  return `<section class="card pred">
    <div class="pred-top"><div><p class="eyebrow">YOUR GOAL</p><h2>${esc(g0.label)}</h2></div>
      <div class="pred-big"><span class="from">${b}%</span>${pick.kind === 'baseline' ? '' : `<span class="arrow">→</span><span class="to">${v}%</span>`}<small>${pick.kind === 'baseline' ? 'chance with your current habits' : `chance with ${esc((PRED_SHORT[pick.id] || pick.label).toLowerCase())}${diff ? ` (${diff > 0 ? '+' : ''}${diff} points)` : ''}`}</small></div></div>
    <div class="pred-chips" role="group" aria-label="Choose a change">${chips}</div>
    <div class="pred-chart" id="predChart">${predChart(p, pick, g0)}<div class="pred-tip" id="predTip" hidden></div></div>
    <div class="pred-foot">${best ? `<span>Most helpful single change: <b>${esc(PRED_SHORT[best.id] || best.label)}</b></span>` : '<span></span>'}
      <button type="button" class="button secondary" data-pred="refresh">Update my prediction ↻</button></div>
    <p class="pred-note">A range of possible futures, not a promise.</p></section>`;
}

const PW = 900, PH = 340, PL = 70, PR = 150, PT = 20, PB = 40;
// the path of the scenario the customer picked (older bridges only sent same habits + all changes)
function predPath(c, pick) {
  if (!pick || pick.kind === 'baseline') return c.todayPath;
  return (c.byScenario && c.byScenario[pick.id]) || c.fullPlan;
}
function predGeom(p) {
  const c = p.chart, n = c.todayPath.p50.length, sc = p.engine.scenarios || [];
  const ends = sc.map(s => parseEur((s.results.range || '').split('–')[1]));
  const all = Object.values(c.byScenario || {}).flatMap(o => o.p90);
  const hi = Math.max(...c.fullPlan.p90, ...c.todayPath.p90, ...all, ...ends) * 1.06;
  const x = i => PL + i / (n - 1) * (PW - PL - PR), y = v => PH - PB - v / hi * (PH - PT - PB);
  return {c, n, hi, x, y};
}
function predChart(p, pick, g0) {
  const {c, n, hi, x, y} = predGeom(p);
  const line = a => a.map((v, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join(' ');
  const band = (lo, up) => line(up) + ' ' + lo.map((v, i) => `L${x(n - 1 - i).toFixed(1)} ${y(lo[n - 1 - i]).toFixed(1)}`).join(' ') + ' Z';
  const plan = predPath(c, pick);
  let g = [0, .5, 1].map(f => `<line x1="${PL}" x2="${PW - PR}" y1="${y(hi * f)}" y2="${y(hi * f)}" stroke="${C.line}"/><text x="${PL - 10}" y="${y(hi * f) + 4}" text-anchor="end" font-size="12" fill="${C.muted}">${k(hi * f)}</text>`).join('');
  g += `<path d="${band(plan.p10, plan.p90)}" fill="${C.blue}" opacity=".09"/>`;
  const target = parseEur(g0.target);
  if (target && target < hi) g += `<line x1="${PL}" x2="${PW - PR}" y1="${y(target)}" y2="${y(target)}" stroke="${C.ok}" stroke-width="1.5" stroke-dasharray="6 5"/><text x="${PL + 6}" y="${y(target) - 7}" font-size="12" fill="${C.ok}" font-weight="700">Goal ${esc(g0.target)}</text>`;
  g += `<path d="${line(c.todayPath.p50)}" fill="none" stroke="${C.base}" stroke-width="2.5"/>`;
  if (pick.kind !== 'baseline') g += `<path class="pred-line" d="${line(plan.p50)}" fill="none" stroke="${C.blue}" stroke-width="3" pathLength="1"/>`;
  // the chosen scenario's range at the end: a whisker on the right
  const [lo, up] = (pick.results.range || '').split('–').map(parseEur), mid = parseEur(pick.results.middle), ex = PW - PR + 34;
  g += `<line x1="${ex}" x2="${ex}" y1="${y(up)}" y2="${y(lo)}" stroke="${pick.kind === 'baseline' ? C.base : C.blue}" stroke-width="10" stroke-linecap="round" opacity=".25"/>
    <circle cx="${ex}" cy="${y(mid)}" r="7" fill="${pick.kind === 'baseline' ? C.base : C.blue}"/>
    <text x="${ex + 14}" y="${y(mid) + 4}" font-size="13" font-weight="700" fill="${C.ink}">${esc(pick.results.middle)}</text>
    <text x="${ex + 14}" y="${y(mid) + 20}" font-size="11" fill="${C.muted}">middle future</text>`;
  g += `<text x="${PL}" y="${PH - 12}" font-size="12" fill="${C.muted}">Today · ${c.startAge}</text><text x="${PW - PR}" y="${PH - 12}" text-anchor="end" font-size="12" fill="${C.muted}">Age ${c.startAge + c.years}</text>`;
  g += `<line id="predX" x1="0" x2="0" y1="${PT}" y2="${PH - PB}" stroke="${C.ink}" stroke-width="1" opacity="0"/><circle id="predA" r="5" fill="${C.base}" opacity="0"/><circle id="predB" r="5" fill="${C.blue}" opacity="0"/>`;
  g += `<rect id="predHit" x="${PL}" y="${PT}" width="${PW - PL - PR}" height="${PH - PT - PB}" fill="transparent"/>`;
  return `<svg viewBox="0 0 ${PW} ${PH}" role="img" aria-label="Your wealth over time with same habits and with your plan. Move along the chart to read each age.">${g}</svg>
    <div class="legend"><span><i style="background:${C.base}"></i>Same habits</span>${pick.kind === 'baseline' ? '' : `<span><i style="background:${C.blue}"></i>${esc(pick.kind === 'combo' ? 'With all changes' : 'With: ' + (PRED_SHORT[pick.id] || pick.label).toLowerCase())}</span>`}<span>Shaded: 8 in 10 futures</span></div>`;
}

function mountPrediction() {
  const box = document.getElementById('predChart');
  if (!box || box.dataset.mounted) return;
  box.dataset.mounted = '1';
  const p = workspace.prediction, svg = box.querySelector('svg'), tip = document.getElementById('predTip');
  const {c, n, x, y} = predGeom(p);
  const pick = p.engine.scenarios.find(s => s.id === PRED.sel) || {}, showPlan = pick.kind !== 'baseline', path = predPath(c, pick);
  const move = ev => {
    const r = svg.getBoundingClientRect(), px = ((ev.touches ? ev.touches[0].clientX : ev.clientX) - r.left) / r.width * PW;
    const i = Math.max(0, Math.min(n - 1, Math.round((px - PL) / (PW - PL - PR) * (n - 1))));
    const a = c.todayPath.p50[i], b = path.p50[i];
    svg.querySelector('#predX').setAttribute('x1', x(i)); svg.querySelector('#predX').setAttribute('x2', x(i)); svg.querySelector('#predX').setAttribute('opacity', .35);
    const A = svg.querySelector('#predA'), B = svg.querySelector('#predB');
    A.setAttribute('cx', x(i)); A.setAttribute('cy', y(a)); A.setAttribute('opacity', 1);
    B.setAttribute('cx', x(i)); B.setAttribute('cy', y(b)); B.setAttribute('opacity', showPlan ? 1 : 0);
    tip.hidden = false;
    tip.innerHTML = `<b>Age ${c.startAge + i}</b><span><i style="background:${C.base}"></i>${k(a)}</span>${showPlan ? `<span><i style="background:${C.blue}"></i>${k(b)}</span>` : ''}`;
    tip.style.left = Math.min(r.width - 150, Math.max(0, x(i) / PW * r.width + 12)) + 'px';
    tip.style.top = Math.max(0, y(Math.max(a, showPlan ? b : 0)) / PH * r.height - 60) + 'px';
  };
  const hide = () => { tip.hidden = true; ['#predX', '#predA', '#predB'].forEach(s => svg.querySelector(s).setAttribute('opacity', 0)); };
  svg.addEventListener('pointermove', move);
  svg.addEventListener('pointerdown', move);
  svg.addEventListener('pointerleave', hide);
}

document.addEventListener('click', async e => {
  const s = e.target.closest('[data-pred-sel]');
  if (s) { PRED.sel = s.dataset.predSel; render(); return; }
  const r = e.target.closest('[data-pred="refresh"]');
  if (!r) return;
  r.disabled = true;
  startPlaying(true);
  render();
  try { await fetch(API + encodeURIComponent(customer) + '/prediction/refresh', {method: 'POST'}); } catch (err) { /* the loader keeps polling */ }
  load();
});
