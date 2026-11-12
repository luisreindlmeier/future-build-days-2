'use strict';
/* My prediction: a short "working on it" sequence tied to the real calculation, then one interactive chart.
   Hover, drag or use the arrow keys to read any age; pick a change (chip or line) to see what it does to your goal;
   zoom the time range, toggle the range band, compare every change at once.
   Uses dashboard.js (workspace, customer, render, load, notify, esc, API, updating) and charts.js (C, k, pctNum, mainGoal).
   Performance: the loader and the chart update in place; nothing here re-renders the whole page on a timer. */
const PRED = {played: {}, playing: null, sel: null, timer: 0, h: null, band: true, all: false, cursor: null, g: null, fresh: true};
const PRED_STEPS = ['Reading your accounts', 'Simulating 2,000 possible futures', 'Testing your choices', 'Checking every number'];
const PRED_SHORT = {baseline: 'Same habits', full_plan: 'All changes', spend_less: 'Spend less', buffer: 'Build a buffer', invest: 'Invest monthly',
  hold_rule: 'Hold in a crash', diversify: 'Diversify', cover: 'Disability cover', close_gap: 'Close spending gap'};

function parseEur(s) {                       // "€2.90m" / "€294k" / "€8,256" -> number
  const m = /€\s?([\d.,]+)\s?([km])?/i.exec(String(s || ''));
  if (!m) return 0;
  return parseFloat(m[1].replace(/,/g, '')) * ({k: 1e3, m: 1e6}[(m[2] || '').toLowerCase()] || 1);
}

const hasData = p => !!(p && p.engine && p.chart && (p.engine.scenarios || []).length);

function predictionPage() {
  const p = workspace.prediction || {};
  const head = header('What your money could do.', 'Thousands of possible futures, built from your own numbers.', 'MY PREDICTION');
  const playing = PRED.playing && PRED.playing.customer === customer;
  if (!PRED.played[customer] && !playing && (p.status === 'READY' || (p.status === 'RUNNING' && !hasData(p)))) startPlaying(false);
  if (PRED.playing && PRED.playing.customer === customer) return head + loader(p.status);
  if (hasData(p) && (p.status === 'READY' || p.status === 'RUNNING')) {
    PRED.fresh = true;
    return head + (p.status === 'RUNNING' ? updating() : '') + result();
  }
  if (p.status === 'RUNNING') { startPlaying(false); return head + loader(p.status); }
  return head + `<div class="card empty"><h2>Your prediction is not available right now.</h2><button class="button secondary" data-pred="refresh">Try again</button></div>`;
}

/* The loader animates by patching only its own DOM node; one full render() when it finishes. */
function startPlaying(refresh) {
  PRED.playing = {customer, start: performance.now(), refresh};
  clearInterval(PRED.timer);
  PRED.timer = setInterval(() => {
    const p = workspace?.prediction || {};
    if (location.hash !== '#future' || !PRED.playing || PRED.playing.customer !== customer) {   // user left: stop, don't replay
      clearInterval(PRED.timer); PRED.playing = null; PRED.played[customer] = true; return;
    }
    const elapsed = performance.now() - PRED.playing.start;
    const ready = p.status === 'READY' || (hasData(p) && !PRED.playing.refresh) || (hasData(p) && elapsed > 6000);
    if (elapsed > 2800 && ready) {
      clearInterval(PRED.timer); PRED.played[customer] = true; PRED.playing = null; render(); return;
    }
    const box = document.querySelector('.pred-loader');
    if (box) box.outerHTML = loader(p.status);
  }, 450);
}

function loader(status) {
  const t = PRED.playing ? performance.now() - PRED.playing.start : 0;
  const ready = status === 'READY';
  const at = Math.min(PRED_STEPS.length - (ready ? 0 : 1), Math.floor(t / 700));     // the last step waits for the real result
  const slow = !ready && t > 8000;
  return `<section class="card pred-loader"><div class="pred-orb"><span></span><span></span><span></span></div>
    <h2>Building your prediction…</h2><ol class="pred-steps">${PRED_STEPS.map((s, i) => `<li class="${i < at ? 'done' : i === at ? 'now' : ''}"><i>${i < at ? '✓' : ''}</i>${s}</li>`).join('')}</ol>
    <div class="pred-progress"><i style="width:${Math.min(100, (at + (ready ? 0 : .5)) / PRED_STEPS.length * 100)}%"></i></div>
    ${slow ? '<p class="sub" style="margin-top:18px">Our AI coach is writing your personal explanation. You can keep using the other pages meanwhile.</p>' : ''}</section>`;
}

function result() {
  const p = workspace.prediction, e = p.engine, f = p.prediction?.output || {}, g0 = mainGoal(e);
  const sc = e.scenarios || [];
  if (!PRED.sel || !sc.some(s => s.id === PRED.sel)) PRED.sel = (sc.find(s => s.kind === 'combo') || sc.find(s => s.kind === 'change') || sc[0]).id;
  const base = sc.find(s => s.kind === 'baseline') || sc[0], pick = sc.find(s => s.id === PRED.sel);
  const b = pctNum(base.results.goal_success[g0.id]), v = pctNum(pick.results.goal_success[g0.id]), diff = v - b;
  const best = sc.find(s => s.id === f.best_change?.scenario_id);
  const chips = sc.map(s => `<button type="button" class="pred-chip${s.id === PRED.sel ? ' on' : ''}${s.kind === 'baseline' ? ' base' : ''}" data-pred-sel="${esc(s.id)}" aria-pressed="${s.id === PRED.sel}">${esc(PRED_SHORT[s.id] || s.label)}<b>${esc(s.results.goal_success[g0.id])}</b></button>`).join('');
  const full = p.chart.todayPath.p50.length - 1;
  const spans = [5, 10].filter(h => h < full).concat([null]);
  const tools = `<div class="pred-tools"><div class="pred-seg" role="group" aria-label="Time range">${spans.map(h => `<button type="button" data-pred-h="${h || 'all'}" class="${(PRED.h || null) === h ? 'on' : ''}">${h ? h + ' years' : 'All ' + full + ' years'}</button>`).join('')}</div>
    <label class="pred-toggle"><input type="checkbox" data-pred-opt="band"${PRED.band ? ' checked' : ''}><span></span>Range of futures</label>
    <label class="pred-toggle"><input type="checkbox" data-pred-opt="all"${PRED.all ? ' checked' : ''}><span></span>Compare all changes</label></div>`;
  return `<section class="card pred${PRED.fresh ? ' enter' : ''}">
    <div class="pred-top"><div><p class="eyebrow">YOUR GOAL</p><h2>${esc(g0.label)}</h2></div>
      <div class="pred-big"><span class="from">${b}%</span>${pick.kind === 'baseline' ? '' : `<span class="arrow">→</span><span class="to" data-count="${v}">${v}%</span>`}<small>${pick.kind === 'baseline' ? 'chance with your current habits' : `chance with ${esc((PRED_SHORT[pick.id] || pick.label).toLowerCase())}${diff ? ` (${diff > 0 ? '+' : ''}${diff} points)` : ''}`}</small></div></div>
    <div class="pred-chips" role="group" aria-label="Choose a change">${chips}</div>
    ${tools}
    <div class="pred-chart" id="predChart">${predChart(p, pick, g0, base)}<div class="pred-tip" id="predTip" hidden></div></div>
    <div class="pred-foot">${best ? `<span>Most helpful single change: <button type="button" class="link" data-pred-sel="${esc(best.id)}"><b>${esc(PRED_SHORT[best.id] || best.label)}</b></button></span>` : '<span></span>'}
      <button type="button" class="button secondary" data-pred="refresh">Update my prediction ↻</button></div>
    <p class="pred-note">A range of possible futures, not a promise. Hover or use ← → to read any age · click a faint line to select that change.</p></section>`;
}

/* ---------- chart ---------- */
const PW = 900, PH = 360, PL = 64, PR = 120, PT = 26, PB = 46;
function predPath(c, pick) {
  if (!pick || pick.kind === 'baseline') return c.todayPath;
  return (c.byScenario && c.byScenario[pick.id]) || c.fullPlan;
}
function niceStep(v) {                       // 1 / 2 / 2.5 / 5 x 10^n, so axis labels are round numbers
  if (v <= 0) return 1;
  const e = Math.pow(10, Math.floor(Math.log10(v))), m = v / e;
  return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10) * e;
}
function smooth(pts) {                       // Catmull-Rom -> cubic Bézier, passes through every yearly point
  if (!pts.length) return '';
  const f = v => v.toFixed(1);
  let d = `M${f(pts[0][0])} ${f(pts[0][1])}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] || pts[i], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2] || p2;
    d += ` C${f(p1[0] + (p2[0] - p0[0]) / 6)} ${f(p1[1] + (p2[1] - p0[1]) / 6)} ${f(p2[0] - (p3[0] - p1[0]) / 6)} ${f(p2[1] - (p3[1] - p1[1]) / 6)} ${f(p2[0])} ${f(p2[1])}`;
  }
  return d;
}
function predGeom(p, pick, g0) {
  const c = p.chart, full = c.todayPath.p50.length - 1;
  const end = Math.min(full, PRED.h || full), n = end + 1;
  const plan = predPath(c, pick), base = c.todayPath, cut = a => (a || []).slice(0, n);
  const vis = [...cut(base.p50), ...cut(plan.p50)];
  if (PRED.band) vis.push(...cut(plan.p90), ...cut(plan.p10));
  if (PRED.all) Object.values(c.byScenario || {}).forEach(o => vis.push(...cut(o.p50)));
  const target = parseEur(g0?.target);
  let top = Math.max(...vis), bottom = Math.min(0, ...vis);
  if (target && target < top * 1.6) top = Math.max(top, target);
  const step = niceStep((top - bottom) * 1.04 / 4);
  top = Math.ceil(top * 1.04 / step) * step;
  bottom = bottom < 0 ? Math.floor(bottom * 1.04 / step) * step : 0;
  const x = i => PL + i / Math.max(1, end) * (PW - PL - PR);
  const y = v => PH - PB - (v - bottom) / (top - bottom) * (PH - PT - PB);
  return {c, n, end, full, top, bottom, step, x, y, plan, base, target, pick};
}
function predChart(p, pick, g0) {
  const G = PRED.g = predGeom(p, pick, g0);
  const {c, n, end, top, bottom, step: yStep, x, y, plan, base, target} = G;
  const pts = a => a.slice(0, n).map((v, i) => [x(i), y(v)]);
  const isBase = pick.kind === 'baseline', col = isBase ? C.muted : C.blue;
  let g = `<defs><linearGradient id="predFill" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="${col}" stop-opacity=".22"/><stop offset="1" stop-color="${col}" stop-opacity="0"/></linearGradient>
    <linearGradient id="predBand" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="${col}" stop-opacity=".16"/><stop offset="1" stop-color="${col}" stop-opacity=".05"/></linearGradient></defs>`;
  // grid + y labels
  const rows = Math.round((top - bottom) / yStep);
  for (let i = 0; i <= rows; i++) {
    const v = bottom + yStep * i;
    g += `<line x1="${PL}" x2="${PW - PR}" y1="${y(v).toFixed(1)}" y2="${y(v).toFixed(1)}" stroke="${C.line}"${v === 0 && bottom < 0 ? ' stroke-width="1.5"' : ' stroke-dasharray="2 4"'}/><text x="${PL - 10}" y="${(y(v) + 4).toFixed(1)}" text-anchor="end" font-size="12" fill="${C.muted}">${k(v)}</text>`;
  }
  // x ticks
  const step = end <= 6 ? 1 : end <= 12 ? 2 : end <= 20 ? 5 : 10;
  for (let i = 0; i <= end; i += step) g += `<text x="${x(i).toFixed(1)}" y="${PH - PB + 22}" text-anchor="middle" font-size="12" fill="${C.muted}">${i === 0 ? 'Today' : 'Age ' + (c.startAge + i)}</text>`;
  if (end % step) g += `<text x="${x(end).toFixed(1)}" y="${PH - PB + 22}" text-anchor="middle" font-size="12" fill="${C.muted}">Age ${c.startAge + end}</text>`;
  // goal line
  if (target && target <= top) g += `<line x1="${PL}" x2="${PW - PR}" y1="${y(target).toFixed(1)}" y2="${y(target).toFixed(1)}" stroke="${C.ok}" stroke-width="1.5" stroke-dasharray="6 5"/><text x="${PL + 8}" y="${(y(target) - 7).toFixed(1)}" font-size="12" fill="${C.ok}" font-weight="700">Goal ${esc(g0.target)}</text>`;
  // other changes as faint, clickable lines
  if (PRED.all) {
    for (const s of p.engine.scenarios) {
      const o = c.byScenario && c.byScenario[s.id];
      if (!o || s.id === pick.id || s.kind === 'baseline') continue;
      const d = smooth(pts(o.p50)), name = esc(PRED_SHORT[s.id] || s.label);
      g += `<g class="pred-ghost" data-pred-sel="${esc(s.id)}"><title>${name}: ${k(o.p50[end])} at age ${c.startAge + end}</title><path d="${d}" fill="none" stroke="#b9c4dc" stroke-width="1.6"/><path d="${d}" fill="none" stroke="transparent" stroke-width="14"/><text x="${(x(end) + 6).toFixed(1)}" y="${(y(o.p50[end]) + 4).toFixed(1)}" font-size="10" fill="#8895ad">${name}</text></g>`;
    }
  }
  // range band + area + lines
  if (PRED.band) {
    const up = pts(plan.p90), lo = pts(plan.p10).reverse();
    g += `<path class="pred-fade" d="${smooth(up)} L${smooth(lo).slice(1)} Z" fill="url(#predBand)"/>`;
  }
  const mid = pts(plan.p50);
  g += `<path class="pred-fade" d="${smooth(mid)} L${x(end).toFixed(1)} ${y(Math.max(0, bottom)).toFixed(1)} L${x(0).toFixed(1)} ${y(Math.max(0, bottom)).toFixed(1)} Z" fill="url(#predFill)"/>`;
  if (!isBase) g += `<path d="${smooth(pts(base.p50))}" fill="none" stroke="${C.base}" stroke-width="2.5" stroke-dasharray="7 5"/>`;
  g += `<path class="pred-line" d="${smooth(mid)}" fill="none" stroke="${col}" stroke-width="3.5" stroke-linecap="round" pathLength="1"/>`;
  // goal reached markers
  const reach = a => target ? a.slice(0, n).findIndex(v => v >= target) : -1;
  const rp = reach(plan.p50), rb = isBase ? -1 : reach(base.p50);
  if (rp > 0) g += `<g class="pred-pop"><circle cx="${x(rp).toFixed(1)}" cy="${y(plan.p50[rp]).toFixed(1)}" r="7" fill="${C.ok}" stroke="white" stroke-width="2.5"/><text x="${x(rp).toFixed(1)}" y="${(y(plan.p50[rp]) - 14).toFixed(1)}" text-anchor="middle" font-size="12" font-weight="700" fill="${C.ok}">Goal at ${c.startAge + rp}</text></g>`;
  if (rb > 0 && rb !== rp) g += `<circle cx="${x(rb).toFixed(1)}" cy="${y(base.p50[rb]).toFixed(1)}" r="5" fill="white" stroke="${C.base}" stroke-width="2.5"><title>Same habits: goal at ${c.startAge + rb}</title></circle>`;
  // end labels
  const ey = y(plan.p50[end]), by = y(base.p50[end]), ex = x(end) + 10;
  g += `<circle cx="${x(end).toFixed(1)}" cy="${ey.toFixed(1)}" r="5" fill="${col}"/><text x="${ex}" y="${(ey + 4).toFixed(1)}" font-size="14" font-weight="700" fill="${C.ink}">${k(plan.p50[end])}</text>`;
  if (!isBase) {
    const byy = Math.abs(by - ey) < 18 ? ey + (by >= ey ? 18 : -18) : by;
    g += `<circle cx="${x(end).toFixed(1)}" cy="${by.toFixed(1)}" r="4" fill="${C.base}"/><text x="${ex}" y="${(byy + 4).toFixed(1)}" font-size="12" fill="${C.muted}">${k(base.p50[end])}</text>`;
  }
  // hover layer
  g += `<line id="predX" x1="0" x2="0" y1="${PT}" y2="${PH - PB}" stroke="${C.ink}" stroke-width="1" opacity="0"/><circle id="predA" r="5" fill="${C.base}" stroke="white" stroke-width="2" opacity="0"/><circle id="predB" r="6" fill="${col}" stroke="white" stroke-width="2" opacity="0"/>`;
  g += `<rect id="predHit" x="${PL}" y="${PT}" width="${PW - PL - PR}" height="${PH - PT - PB}" fill="transparent"/>`;
  const label = isBase ? 'Same habits' : pick.kind === 'combo' ? 'With all changes' : 'With: ' + (PRED_SHORT[pick.id] || pick.label).toLowerCase();
  return `<svg viewBox="0 0 ${PW} ${PH}" tabindex="0" role="img" aria-label="Your wealth over time, ${esc(label)}${isBase ? '' : ' compared with same habits'}. Use the arrow keys to read each age.">${g}</svg>
    <div class="legend">${isBase ? '' : `<span><i style="background:${C.base}"></i>Same habits</span>`}<span><i style="background:${col}"></i>${esc(label)}</span>${PRED.band ? '<span><i class="band"></i>8 in 10 futures</span>' : ''}${target ? `<span><i style="background:${C.ok}"></i>Your goal</span>` : ''}</div>`;
}

function mountPrediction() {
  const box = document.getElementById('predChart');
  if (!box || box.dataset.mounted) return;
  box.dataset.mounted = '1';
  PRED.fresh = false;
  const svg = box.querySelector('svg'), tip = document.getElementById('predTip'), G = PRED.g;
  if (!svg || !G) return;
  const {c, n, end, x, y, plan, base, pick} = G, showBase = pick.kind !== 'baseline';
  const X = svg.querySelector('#predX'), A = svg.querySelector('#predA'), B = svg.querySelector('#predB');
  const show = i => {
    PRED.cursor = i;
    const r = svg.getBoundingClientRect(), a = base.p50[i], b = plan.p50[i];
    X.setAttribute('x1', x(i)); X.setAttribute('x2', x(i)); X.setAttribute('opacity', .3);
    A.setAttribute('cx', x(i)); A.setAttribute('cy', y(a)); A.setAttribute('opacity', showBase ? 1 : 0);
    B.setAttribute('cx', x(i)); B.setAttribute('cy', y(b)); B.setAttribute('opacity', 1);
    const d = b - a;
    tip.hidden = false;
    tip.innerHTML = `<b>${i === 0 ? 'Today' : `In ${i} year${i > 1 ? 's' : ''}`} · age ${c.startAge + i}</b>
      <span><i style="background:${showBase ? C.blue : C.muted}"></i>${k(b)} <small>middle future</small></span>
      ${PRED.band ? `<span class="rng">8 in 10: ${k(plan.p10[i])} – ${k(plan.p90[i])}</span>` : ''}
      ${showBase ? `<span><i style="background:${C.base}"></i>${k(a)} <small>same habits</small></span>${i ? `<span class="${d >= 0 ? 'up' : 'down'}">${d >= 0 ? '+' : '−'}${k(Math.abs(d))} difference</span>` : ''}` : ''}`;
    const left = x(i) / PW * r.width;
    tip.style.left = (left > r.width * .6 ? left - tip.offsetWidth - 14 : left + 14) + 'px';
    tip.style.top = Math.max(0, Math.min(y(Math.max(a, b)), y(b)) / PH * r.height - 30) + 'px';
  };
  const at = ev => {
    const r = svg.getBoundingClientRect(), px = ((ev.touches ? ev.touches[0].clientX : ev.clientX) - r.left) / r.width * PW;
    return Math.max(0, Math.min(end, Math.round((px - PL) / (PW - PL - PR) * end)));
  };
  const hide = () => { tip.hidden = true; [X, A, B].forEach(el => el.setAttribute('opacity', 0)); };
  svg.addEventListener('pointermove', ev => { if (!ev.target.closest('.pred-ghost')) show(at(ev)); });
  svg.addEventListener('pointerdown', ev => { if (!ev.target.closest('.pred-ghost')) show(at(ev)); });
  svg.addEventListener('pointerleave', hide);
  svg.addEventListener('blur', hide);
  svg.addEventListener('keydown', ev => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(ev.key)) return;
    ev.preventDefault();
    const cur = PRED.cursor ?? 0;
    show(ev.key === 'Home' ? 0 : ev.key === 'End' ? end : Math.max(0, Math.min(end, cur + (ev.key === 'ArrowRight' ? 1 : -1))));
  });
  // count the big number up when the scenario changes
  const to = document.querySelector('.pred-big .to[data-count]');
  if (to && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const target = +to.dataset.count, from = +(PRED.lastPct ?? target), t0 = performance.now();
    PRED.lastPct = target;
    if (from !== target) {
      const tick = now => { const q = Math.min(1, (now - t0) / 500); to.textContent = Math.round(from + (target - from) * (1 - Math.pow(1 - q, 3))) + '%'; if (q < 1) requestAnimationFrame(tick); };
      requestAnimationFrame(tick);
    }
  }
}

/* Re-draw only the prediction card (not the whole page) when the customer plays with the chart. */
function redrawPrediction() {
  const card = document.querySelector('section.pred');
  if (!card) return render();
  card.outerHTML = result();
  mountPrediction();
}

document.addEventListener('click', async e => {
  const s = e.target.closest('[data-pred-sel]');
  if (s) { PRED.sel = s.dataset.predSel; redrawPrediction(); return; }
  const h = e.target.closest('[data-pred-h]');
  if (h) { PRED.h = h.dataset.predH === 'all' ? null : +h.dataset.predH; PRED.cursor = null; redrawPrediction(); return; }
  const r = e.target.closest('[data-pred="refresh"]');
  if (!r) return;
  r.disabled = true;
  startPlaying(true);
  render();
  try { await fetch(API + encodeURIComponent(customer) + '/prediction/refresh', {method: 'POST'}); } catch (err) { /* the loader keeps polling */ }
  load();
});
document.addEventListener('change', e => {
  const o = e.target.closest('[data-pred-opt]');
  if (!o) return;
  PRED[o.dataset.predOpt] = o.checked;
  redrawPrediction();
});
