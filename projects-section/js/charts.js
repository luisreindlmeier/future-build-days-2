'use strict';
/* Kairos charts: data-driven SVG, no libraries. Every mark has a direct label or a <title> tooltip,
   status colours always come with an icon and a word, never colour alone. */
const C = {blue: '#0018a8', blue2: '#4a63d9', base: '#9aa7ba', ink: '#152a46', muted: '#5c6b7e', line: '#dee5ed',
  ok: '#16745e', watch: '#b07a1e', bad: '#b3412e', soilLo: '#e9dfcc', soilHi: '#8a6a43', bark: '#7a6650'};
const STATUS = {HEALTHY: {c: C.ok, icon: '✓', word: 'on track'}, WILTING: {c: C.watch, icon: '!', word: 'watch'},
  ROTTEN: {c: C.bad, icon: '✕', word: 'over budget'}};
const LEAF = {HEALTHY: ['#3f8f72', '#5aa386', '#2f7a60', '#76b79c'], WILTING: ['#c99a3e', '#d9b05c', '#b8862c', '#e3c27a'],
  ROTTEN: ['#b3412e', '#c4614d', '#9c3424', '#d18270']};
const k = v => { const a = Math.abs(v); return '€' + (a >= 1e6 ? (v / 1e6).toFixed(2).replace(/\.?0+$/, '') + 'm' : a >= 1e4 ? Math.round(v / 1e3) + 'k' : a >= 1e3 ? (v / 1e3).toFixed(1).replace(/\.0$/, '') + 'k' : Math.round(v)); };
const pctNum = s => parseFloat(String(s).replace(/[^\d.\-]/g, '')) || 0;
const t = (x, y, s, o = {}) => `<text x="${x.toFixed(1)}" y="${y.toFixed(1)}" font-size="${o.size || 12}" fill="${o.fill || C.ink}" text-anchor="${o.anchor || 'start'}"${o.weight ? ` font-weight="${o.weight}"` : ''}${o.halo ? ` stroke="${o.halo}" stroke-width="4" stroke-linejoin="round" paint-order="stroke"` : ''}>${esc(s)}</text>`;
const HALO = '#f0f6f7';

/* ------------------------------------------------------------------ the wealth tree */
function treeView(tr) {
  const W = 760, H = 640, cx = 380, crownTop = 92, rowGap = 134, trunkTop = 308, ground = 456;
  const leaves = [...(tr.leaves || [])].sort((a, b) => (b.monthlyAmount || 0) - (a.monthlyAmount || 0)).slice(0, 8);
  let g = '';
  const wx = {CALM: ['☀', 'Calm'], BREEZY: ['☁', 'Breezy'], WINDY: ['≋', 'Windy'], STORM: ['⛈', 'Storm']}[tr.weather?.type] || ['☀', 'Calm'];
  g += `<g><title>${esc(tr.weather?.reason || '')}</title>${t(W - 16, 26, wx[0] + ' ' + wx[1], {anchor: 'end', size: 13, fill: C.muted})}</g>`;
  // crown: two even rows of leaf clusters (largest spending first), label centred under each
  const n = leaves.length, rowA = Math.ceil(n / 2), rowB = n - rowA;
  const pos = leaves.map((l, i) => {
    const row = i < rowA ? 0 : 1, m = row ? rowB : rowA, j = row ? i - rowA : i, span = row ? 520 : 600;
    return {x: cx + (m === 1 ? 0 : (j / (m - 1) - .5) * span), y: crownTop + row * rowGap};
  });
  // twigs from the trunk top to each cluster (drawn first, behind)
  pos.forEach(p => { g += `<path d="M${cx} ${trunkTop + 6} Q ${(cx + p.x) / 2} ${(trunkTop + p.y) / 2 + 20}, ${p.x} ${p.y + 10}" fill="none" stroke="${C.bark}" stroke-width="2.4" opacity=".45"/>`; });
  leaves.forEach((l, i) => {
    const {x, y} = pos[i], r = 18 + (l.size || .3) * 20;
    const st = STATUS[l.health] || STATUS.HEALTHY, pal = LEAF[l.health] || LEAF.HEALTHY;
    let blobs = '';
    for (let j = 0; j < 9; j++) {
      const aa = j * 2.4, rr = j ? r * (.45 + (j % 3) * .2) : 0, bx = x + Math.cos(aa) * rr, by = y + Math.sin(aa) * rr * .75;
      blobs += `<ellipse cx="${bx.toFixed(1)}" cy="${by.toFixed(1)}" rx="${(r * .48).toFixed(1)}" ry="${(r * .32).toFixed(1)}" transform="rotate(${j * 37} ${bx.toFixed(1)} ${by.toFixed(1)})" fill="${pal[j % 4]}"/>`;
    }
    const ratio = l.peerAverage > 0 ? l.monthlyAmount / l.peerAverage : null;
    g += `<g class="zone" data-zone="leaves"><title>${esc(l.detail || '')}</title>${blobs}
      <circle cx="${x + r * .8}" cy="${y - r * .7}" r="9" fill="${st.c}" stroke="#fff" stroke-width="2"/>${t(x + r * .8, y - r * .7 + 4, st.icon, {anchor: 'middle', size: 11, fill: '#fff', weight: 700})}
      ${t(x, y + r + 16, l.label, {anchor: 'middle', weight: 700, halo: HALO})}${t(x, y + r + 31, `${k(l.monthlyAmount)}/mo` + (ratio && ratio >= 1.2 ? ` · ${ratio.toFixed(1)}× peers` : ''), {anchor: 'middle', size: 11, fill: C.muted, halo: HALO})}</g>`;
  });
  // trunk: investing
  const tk = tr.trunk || {thickness: .3, cracks: 0};
  const tw = 20 + (tk.thickness || 0) * 34;
  g += `<g class="zone" data-zone="trunk"><title>${esc(tk.detail || '')}</title>
    <path d="M${cx - tw / 2} ${ground} L${cx - tw * .3} ${trunkTop} L${cx + tw * .3} ${trunkTop} L${cx + tw / 2} ${ground} Z" fill="${C.bark}"/>
    ${Array.from({length: Math.min(4, tk.cracks || 0)}, (_, i) => `<path d="M${cx - 4 + i * 3} ${340 + i * 24} l6 6 l-5 6 l6 6" fill="none" stroke="#3f3326" stroke-width="1.6"/>`).join('')}
    ${t(cx + tw / 2 + 12, 398, 'Trunk · investing', {weight: 700})}${t(cx + tw / 2 + 12, 414, k(tk.invested || 0) + ((tk.cracks || 0) ? ` · ${tk.cracks} risk${tk.cracks > 1 ? 's' : ''} (cracks)` : ''), {size: 11, fill: C.muted})}</g>`;
  // branches: projects, on the left of the trunk below the crown
  (tr.branches || []).slice(0, 2).forEach((b, i) => {
    const y = 372 + i * 34, len = 60 + (b.length || 0) * 70, x1 = cx - tw * .35 - len, yy = y - 18;
    g += `<g><title>${esc(b.detail || '')}</title><path d="M${cx - tw * .32} ${y} Q ${cx - tw * .35 - len * .6} ${y - 2}, ${x1} ${yy}" fill="none" stroke="${C.bark}" stroke-width="5" stroke-linecap="round"/>
      <circle cx="${x1}" cy="${yy}" r="7" fill="${b.fruit ? C.ok : b.blossom ? '#e2a6b9' : '#fff'}" stroke="${C.bark}" stroke-width="2"/>
      ${t(x1 - 12, yy + 4, `Project: ${b.name} · ${Math.round((b.length || 0) * 100)}%`, {anchor: 'end', size: 11, fill: C.muted, halo: HALO})}</g>`;
  });
  // soil band: learning
  const soil = tr.soil || {richness: 0};
  const mix = (a, b, f) => '#' + [0, 2, 4].map(i => Math.round(parseInt(a.substr(1 + i, 2), 16) * (1 - f) + parseInt(b.substr(1 + i, 2), 16) * f).toString(16).padStart(2, '0')).join('');
  g += `<g class="zone" data-zone="soil"><title>${esc(soil.detail || '')}</title><rect x="40" y="${ground}" width="${W - 80}" height="26" rx="4" fill="${mix(C.soilLo, C.soilHi, soil.richness || 0)}"/>
    ${t(54, ground + 17, `Soil · learning ${Math.round((soil.richness || 0) * 100)}/100`, {size: 12, fill: (soil.richness || 0) > .55 ? '#fff' : C.ink, weight: 700})}</g>`;
  // roots: savings pots, spread evenly, depth = how full the pot is
  const roots = tr.roots || [], m = roots.length;
  roots.forEach((r, i) => {
    const x1 = cx + (m === 1 ? 0 : (i / (m - 1) - .5) * 520), y0 = ground + 26, y1 = y0 + 34 + Math.min(1, r.depth || 0) * 80;
    const col = r.status === 'NEEDS_CARE' || (r.health || 0) < .4 ? C.watch : C.ok;
    const hasTarget = r.target > 1, pct = hasTarget ? Math.round(Math.min(1, r.balance / r.target) * 100) : null;
    const amount = !hasTarget && !r.balance ? 'not set up yet' : k(r.balance) + (hasTarget ? ' of ' + k(r.target) + ` · ${pct}%` : '');
    g += `<g class="zone" data-zone="roots"><title>${esc(r.detail || '')}</title>
      <path d="M${cx + (x1 - cx) * .06} ${y0} C ${cx + (x1 - cx) * .2} ${y0 + 40}, ${x1} ${y1 - 50}, ${x1} ${y1}" fill="none" stroke="${C.bark}" stroke-width="${3 + (r.thickness || 0) * 7}" stroke-linecap="round"/>
      <circle cx="${x1}" cy="${y1}" r="6" fill="${col}"/>
      ${t(x1, y1 + 20, r.label.replace(' roots', '') + ' savings', {anchor: 'middle', weight: 700})}
      ${t(x1, y1 + 35, amount, {anchor: 'middle', size: 11, fill: C.muted})}</g>`;
  });
  return `<svg class="tree-svg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Your wealth tree. Leaves: spending per category, coloured by health. Trunk: investing. Roots: savings pots. Soil: learning.">${g}</svg>
    <div class="tree-legend"><span><i style="background:${C.ok}">✓</i>on track</span><span><i style="background:${C.watch}">!</i>watch</span><span><i style="background:${C.bad}">✕</i>over budget</span>
    <span class="key">Leaves = spending · Trunk = investing · Roots = savings · Soil = learning · hover any part</span></div>`;
}

/* ------------------------------------------------------------------ spending vs people like you */
function spendBars(leaves) {
  const rows = [...(leaves || [])].filter(l => l.monthlyAmount > 0).sort((a, b) => b.monthlyAmount - a.monthlyAmount);
  if (!rows.length) return '';
  const W = 520, L = 104, R = 120, rowH = 30, H = rows.length * rowH + 26;
  const max = Math.max(...rows.map(r => Math.max(r.monthlyAmount, r.peerAverage || 0))) * 1.05;
  const x = v => L + v / max * (W - L - R);
  let g = '';
  rows.forEach((r, i) => {
    const y = 8 + i * rowH, st = STATUS[r.health] || STATUS.HEALTHY;
    g += `<g><title>${esc(r.detail || '')}</title>${t(L - 10, y + 15, r.label, {anchor: 'end', size: 12})}
      <rect x="${L}" y="${y + 4}" width="${Math.max(3, x(r.monthlyAmount) - L)}" height="16" rx="3" fill="${st.c}" opacity="${r.health === 'HEALTHY' ? .55 : .9}"/>
      ${r.peerAverage ? `<line x1="${x(r.peerAverage)}" x2="${x(r.peerAverage)}" y1="${y}" y2="${y + 24}" stroke="${C.ink}" stroke-width="2"/>` : ''}
      ${t(x(Math.max(r.monthlyAmount, r.peerAverage || 0)) + 8, y + 16, `${k(r.monthlyAmount)} ${st.icon}`, {size: 12, fill: C.ink, weight: 700})}</g>`;
  });
  g += `<line x1="${W - R + 18}" x2="${W - R + 18}" y1="${H - 14}" y2="${H - 2}" stroke="${C.ink}" stroke-width="2"/>${t(W - R + 24, H - 4, 'people like you', {size: 11, fill: C.muted})}`;
  return `<svg class="chart-svg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Monthly spending per category compared with similar households">${g}</svg>`;
}

/* ------------------------------------------------------------------ health over time */
function healthTrend(snaps) {
  const s = (snaps || []).filter(x => x.treeHealth != null);
  if (s.length < 2) return `<p class="sub">Your trend appears after the first month. <button class="link" data-command="month">Advance one demo month →</button></p>`;
  const W = 520, H = 190, L = 34, R = 20, T = 14, B = 26;
  const lo = Math.max(0, Math.min(...s.map(x => x.treeHealth)) - 8), hi = Math.min(100, Math.max(...s.map(x => x.treeHealth)) + 8);
  const x = i => L + i / (s.length - 1) * (W - L - R), y = v => T + (1 - (v - lo) / (hi - lo || 1)) * (H - T - B);
  const pts = s.map((p, i) => `${x(i).toFixed(1)},${y(p.treeHealth).toFixed(1)}`).join(' ');
  let g = [lo, Math.round((lo + hi) / 2), hi].map(v => `<line x1="${L}" x2="${W - R}" y1="${y(v)}" y2="${y(v)}" stroke="${C.line}"/>${t(L - 6, y(v) + 4, Math.round(v), {anchor: 'end', size: 11, fill: C.muted})}`).join('');
  g += `<polyline points="${pts}" fill="none" stroke="${C.blue}" stroke-width="2.5" stroke-linejoin="round"/>`;
  g += s.map((p, i) => `<g><title>${esc(p.month)}: health ${p.treeHealth}${p.events?.length ? ' · ' + p.events.join(' · ') : ''}</title><circle cx="${x(i)}" cy="${y(p.treeHealth)}" r="${i === s.length - 1 ? 5 : 3.5}" fill="#fff" stroke="${C.blue}" stroke-width="2"/></g>`).join('');
  g += t(x(s.length - 1), y(s.at(-1).treeHealth) - 10, s.at(-1).treeHealth, {anchor: 'middle', weight: 700});
  g += t(L, H - 6, s[0].month, {size: 11, fill: C.muted}) + t(W - R, H - 6, s.at(-1).month, {anchor: 'end', size: 11, fill: C.muted});
  return `<svg class="chart-svg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Tree health per month">${g}</svg>`;
}

/* ------------------------------------------------------------------ goal chance per scenario */
function mainGoal(engine) { return [...(engine?.customer?.goals || [])].sort((a, b) => a.priority - b.priority)[0]; }
function goalBars(engine) {
  const g0 = mainGoal(engine);
  if (!g0) return '';
  const SHORT = {spend_less: 'Spend less', buffer: 'Build a buffer', invest: 'Invest monthly', hold_rule: 'Hold in a crash',
    diversify: 'Diversify', cover: 'Disability cover', close_gap: 'Close spending gap'};
  const rows = (engine.scenarios || []).map(s => ({label: s.kind === 'baseline' ? 'Same habits' : s.kind === 'combo' ? 'All changes together' : SHORT[s.id] || s.label.replace(/\s*\(.*\)$/, ''),
    v: pctNum(s.results.goal_success[g0.id]), base: s.kind === 'baseline', combo: s.kind === 'combo'}));
  const base = rows.find(r => r.base);
  const sorted = [base, ...rows.filter(r => !r.base).sort((a, b) => b.v - a.v)].filter(Boolean);
  const W = 520, L = 196, R = 46, rowH = 30, H = sorted.length * rowH + 8;
  const x = v => L + v / 100 * (W - L - R);
  let g = '';
  sorted.forEach((r, i) => {
    const y = 4 + i * rowH, label = r.label.length > 30 ? r.label.slice(0, 28) + '…' : r.label;
    g += `<g><title>${esc(r.label)}: ${r.v}%</title>${t(L - 10, y + 16, label, {anchor: 'end', size: 12, weight: r.base || r.combo ? 700 : 400})}
      <rect x="${L}" y="${y + 5}" width="${Math.max(2, x(r.v) - L)}" height="16" rx="3" fill="${r.base ? C.base : r.combo ? C.blue : C.blue2}"/>
      ${t(x(r.v) + 8, y + 18, r.v + '%', {weight: 700})}</g>`;
  });
  if (base) g = `<line x1="${x(base.v)}" x2="${x(base.v)}" y1="0" y2="${H}" stroke="${C.base}" stroke-dasharray="3 3"/>` + g;
  return `<svg class="chart-svg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Chance of reaching ${esc(g0.label)} in each scenario">${g}</svg>`;
}

/* ------------------------------------------------------------------ risks: same habits vs all changes */
function riskDots(engine) {
  const sc = engine?.scenarios || [], base = sc.find(s => s.kind === 'baseline');
  const plan = sc.find(s => s.kind === 'combo') || sc.find(s => s.kind === 'change');
  if (!base || !plan) return '';
  const rows = [];
  (base.results.events || []).forEach(e => {
    const p = (plan.results.events || []).find(x => x.id === e.id);
    if (!p) return;
    const name = {company_shock: 'Company shock: wealth hit', panic_sale: 'Selling in a crash', income_gap: 'Year without income'}[e.id] || e.label;
    if (e.id === 'company_shock') rows.push({name, a: pctNum(e.typical_hit), b: pctNum(p.typical_hit)});
    else rows.push({name, a: pctNum(e.chance), b: pctNum(p.chance)});
  });
  rows.push({name: 'Ending below today', a: pctNum(base.results.risk_below_today), b: pctNum(plan.results.risk_below_today)});
  const W = 520, L = 196, R = 30, rowH = 34, H = rows.length * rowH + 30;
  const x = v => L + v / 100 * (W - L - R);
  let g = [0, 50, 100].map(v => `<line x1="${x(v)}" x2="${x(v)}" y1="0" y2="${H - 24}" stroke="${C.line}"/>${t(x(v), H - 8, v + '%', {anchor: 'middle', size: 11, fill: C.muted})}`).join('');
  rows.forEach((r, i) => {
    const y = 14 + i * rowH;
    g += `<g><title>${esc(r.name)}: ${r.a}% with same habits, ${r.b}% with ${esc(plan.kind === 'combo' ? 'all changes' : plan.label)}</title>${t(L - 10, y + 4, r.name, {anchor: 'end', size: 12})}
      <line x1="${x(r.a)}" x2="${x(r.b)}" y1="${y}" y2="${y}" stroke="${C.base}" stroke-width="3"/>
      <circle cx="${x(r.a)}" cy="${y}" r="6" fill="${C.base}"/><circle cx="${x(r.b)}" cy="${y}" r="6" fill="${C.blue}"/>
      ${t(x(Math.max(r.a, r.b)) + 12, y + 4, `${r.a}% → ${r.b}%`, {size: 11, fill: C.muted})}</g>`;
  });
  return `<svg class="chart-svg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Risks with same habits and with the plan">${g}</svg>
    <div class="legend inline"><span><i style="background:${C.base}"></i>Same habits</span><span><i style="background:${C.blue}"></i>${plan.kind === 'combo' ? 'All changes together' : esc(plan.label)}</span></div>`;
}

/* ------------------------------------------------------------------ effect of each action on the goal */
function impactBars(actions) {
  const rows = (actions || []).map(a => {
    const im = a.impact || {}, lab = im.effect_label || '';
    let v = 0;
    const m = /([+−-]?\d+) points?/.exec(lab);
    if (m) v = Math.abs(parseInt(m[1].replace('−', '-'), 10));
    return {title: a.title, v, protect: !v, lab, keeps: /^keeps/.test(lab)};
  });
  if (!rows.length) return '';
  const W = 900, L = 380, R = 120, rowH = 30, H = rows.length * rowH + 6;
  const max = Math.max(5, ...rows.map(r => r.v));
  const x = v => L + v / max * (W - L - R);
  let g = '';
  rows.forEach((r, i) => {
    const y = 3 + i * rowH, title = r.title.length > 58 ? r.title.slice(0, 56) + '…' : r.title;
    g += `<g><title>${esc(r.title)}: ${esc(r.lab)}</title>${t(L - 10, y + 16, title, {anchor: 'end', size: 12})}
      ${r.protect ? `${t(L + 2, y + 17, '🛡 protects', {size: 12, fill: C.muted})}`
        : `<rect x="${L}" y="${y + 5}" width="${x(r.v) - L}" height="16" rx="3" fill="${r.keeps ? C.blue2 : C.blue}" opacity="${r.keeps ? .55 : 1}"/>${t(x(r.v) + 8, y + 18, (r.keeps ? 'keeps ' : '+') + r.v + ' pts', {weight: 700})}`}</g>`;
  });
  return `<svg class="chart-svg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Effect of each step on your main goal, in percentage points">${g}</svg>`;
}

/* ------------------------------------------------------------------ how long each agent step took */
function timingBars(p) {
  const tm = p.engine?.timings;
  if (!tm) return '';
  const att = r => ((r?.validation || {}).attempts || []);
  const rows = [{name: 'Simulation engine', segs: [{s: tm.engine_seconds || 0, ok: true, lab: 'done'}]},
    {name: 'Prediction agent', segs: att(p.prediction).map(a => ({s: a.seconds || 0, ok: !Object.keys(a.violations || {}).length, lab: 'attempt ' + a.attempt}))},
    {name: 'Action agent', segs: att(p.actions).map(a => ({s: a.seconds || 0, ok: !Object.keys(a.violations || {}).length, lab: 'attempt ' + a.attempt}))}];
  const total = Math.max(1, ...rows.map(r => (r.name === 'Simulation engine' ? 0 : tm.engine_seconds || 0) + r.segs.reduce((a, b) => a + b.s, 0)));
  const W = 900, L = 160, R = 70, rowH = 32, H = rows.length * rowH + 28;
  const x = v => L + v / total * (W - L - R);
  let g = '';
  rows.forEach((r, i) => {
    const y = 4 + i * rowH;
    let at = r.name === 'Simulation engine' ? 0 : tm.engine_seconds || 0;
    g += t(L - 10, y + 16, r.name, {anchor: 'end', size: 12});
    r.segs.forEach(sg => {
      g += `<g><title>${esc(r.name)} · ${esc(sg.lab)}: ${sg.s.toFixed(1)} s · ${sg.ok ? 'passed the guardrail' : 'guardrail found problems, sent back'}</title>
        <rect x="${x(at)}" y="${y + 5}" width="${Math.max(3, x(at + sg.s) - x(at) - 2)}" height="16" rx="3" fill="${sg.ok ? C.ok : C.watch}"/></g>`;
      at += sg.s;
    });
    g += t(x(at) + 6, y + 18, at.toFixed(1) + ' s', {size: 11, fill: C.muted});
  });
  g += `<line x1="${L}" x2="${W - R}" y1="${H - 20}" y2="${H - 20}" stroke="${C.line}"/>${t(L, H - 4, '0 s', {size: 11, fill: C.muted})}${t(W - R, H - 4, total.toFixed(1) + ' s', {anchor: 'end', size: 11, fill: C.muted})}`;
  return `<svg class="chart-svg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Time per step; the agents run in parallel after the engine">${g}</svg>
    <div class="legend inline"><span><i style="background:${C.ok}"></i>passed the guardrail</span><span><i style="background:${C.watch}"></i>problems found, sent back to fix</span></div>`;
}
