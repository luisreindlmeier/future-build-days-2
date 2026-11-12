'use strict';
/* FinPulse 2.5D wealth tree, drawn to look like a real tree.
   A grassy soil platform with a cut-away front showing the roots (savings), a tapered trunk with bark (investing),
   and one leafy bough per spending category on real limbs around the trunk: lush green when on track, yellowing
   when to watch, thinning and brown with falling leaves when over budget. Drag or use the arrows to turn it;
   tap any part to bring it forward and see its numbers. Uses charts.js helpers (C, STATUS, k, t, esc). */
const T3 = {tr: null, rot: 0, target: null, sel: null, drag: null, raf: 0, touched: false, moved: false, leaves: []};
const reducedMotion = () => window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
const FOLIAGE = {
  HEALTHY: {dark: '#1d5a3f', mid: '#2f8a5f', light: '#6cc393', leaf: '#3da06f'},
  WILTING: {dark: '#6f6420', mid: '#b29a32', light: '#e3cd6a', leaf: '#c9b040'},
  ROTTEN: {dark: '#5f2716', mid: '#a04a2c', light: '#d08458', leaf: '#b7603a'},
};
const BARK = {dark: '#3d2f22', mid: '#6b5440', light: '#9c8468'};

/* deterministic pseudo-random numbers, so the tree looks the same on every redraw */
function rnd(seed) { let s = seed * 9301 + 49297; return () => { s = (s * 9301 + 49297) % 233280; return s / 233280; }; }

/* a branch that thins from w0 to w1 along a quadratic curve p0 -> c -> p1 */
function limb(p0, c, p1, w0, w1, fill, opacity = 1) {
  const L = [], R = [], N = 12;
  for (let i = 0; i <= N; i++) {
    const u = i / N, a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, d = u * u;
    const x = a * p0[0] + b * c[0] + d * p1[0], y = a * p0[1] + b * c[1] + d * p1[1];
    const dx = 2 * (1 - u) * (c[0] - p0[0]) + 2 * u * (p1[0] - c[0]), dy = 2 * (1 - u) * (c[1] - p0[1]) + 2 * u * (p1[1] - c[1]);
    const len = Math.hypot(dx, dy) || 1, w = (w0 + (w1 - w0) * u) / 2;
    L.push([x - dy / len * w, y + dx / len * w]);
    R.push([x + dy / len * w, y - dx / len * w]);
  }
  const pts = L.concat(R.reverse()).map((q, i) => (i ? 'L' : 'M') + q[0].toFixed(1) + ' ' + q[1].toFixed(1)).join(' ');
  return `<path d="${pts} Z" fill="${fill}" opacity="${opacity}"/>`;
}

function tree3d(tr) {
  T3.tr = tr;
  const leaves = [...(tr.leaves || [])].sort((a, b) => (b.monthlyAmount || 0) - (a.monthlyAmount || 0)).slice(0, 8);
  T3.leaves = leaves;
  const chips = leaves.map((l, i) => {
    const st = STATUS[l.health] || STATUS.HEALTHY;
    return `<button type="button" class="t3-chip" data-t3="leaf:${i}"><i style="background:${st.c}">${st.icon}</i>${esc(l.label)} <b>${k(l.monthlyAmount)}</b></button>`;
  }).join('');
  return `<div class="t3">
    <div class="t3-stage"><svg id="t3svg" viewBox="0 0 760 640" role="img" aria-label="Your wealth tree. Drag to turn it. Each leafy bough is one spending category, the trunk is investing, the roots in the soil are your savings, the soil is learning."></svg>
      <div class="t3-turn"><button type="button" data-t3="left" aria-label="Turn the tree left">‹</button><span>drag to turn · tap a part</span><button type="button" data-t3="right" aria-label="Turn the tree right">›</button></div></div>
    <aside class="t3-info" id="t3info" aria-live="polite"></aside>
    <div class="t3-chips">${chips}<button type="button" class="t3-chip" data-t3="trunk"><i style="background:${C.bark}">↑</i>Investing</button>
      <button type="button" class="t3-chip" data-t3="roots"><i style="background:${C.ok}">↓</i>Savings</button><button type="button" class="t3-chip" data-t3="soil"><i style="background:${C.soilHi}">≋</i>Learning</button></div>
    <div class="tree-legend"><span><i style="background:${C.ok}">✓</i>lush: on track</span><span><i style="background:${C.watch}">!</i>yellowing: watch</span><span><i style="background:${C.bad}">✕</i>losing leaves: over budget</span></div>
  </div>`;
}

function mountTree3d() {
  const svg = document.getElementById('t3svg');
  if (!svg || svg.dataset.mounted) return;
  svg.dataset.mounted = '1';
  T3.target = null;
  T3.moved = false;
  svg.addEventListener('pointerdown', e => { T3.drag = {x: e.clientX, rot: T3.rot}; T3.moved = false; });
  svg.addEventListener('pointermove', e => {
    if (!T3.drag) return;
    const dx = e.clientX - T3.drag.x;
    if (Math.abs(dx) > 5 && !T3.moved) { T3.moved = true; T3.touched = true; try { svg.setPointerCapture(e.pointerId); } catch (err) { /* ok */ } }
    if (!T3.moved) return;
    T3.rot = T3.drag.rot + dx * 0.012;
    T3.target = null;
    draw3d();
  });
  const end = e => {
    const wasDrag = T3.moved;
    T3.drag = null;
    T3.moved = false;
    if (wasDrag || e.type !== 'pointerup') return;
    const hit = document.elementFromPoint(e.clientX, e.clientY);          // works even while the tree is redrawn
    const part = hit && hit.closest && hit.closest('[data-part]');
    if (part) select3d(part.dataset.part);
  };
  svg.addEventListener('pointerup', end);
  svg.addEventListener('pointercancel', end);
  svg.addEventListener('pointerleave', () => { if (!T3.moved) T3.drag = null; });
  const deep = new URLSearchParams(location.search).get('part');   // deep link, e.g. ?user=max&part=leaf:1
  if (deep && /^(leaf|root|branch):\d+$|^(trunk|soil|roots)$/.test(deep) && T3.sel !== deep) { select3d(deep); T3.rot = T3.target ?? T3.rot; T3.target = null; }
  info3d();
  draw3d();
  cancelAnimationFrame(T3.raf);
  const tick = () => {
    if (!document.getElementById('t3svg')) return;
    if (T3.target != null) {
      const d = T3.target - T3.rot;
      if (Math.abs(d) < 0.002) { T3.rot = T3.target; T3.target = null; } else T3.rot += d * 0.14;
      draw3d();
    } else if (!T3.touched && !T3.drag && !reducedMotion()) {
      T3.rot += 0.0022;
      draw3d();
    }
    T3.raf = requestAnimationFrame(tick);
  };
  T3.raf = requestAnimationFrame(tick);
}

const ringAngle = i => (2 * Math.PI * i) / Math.max(1, T3.leaves.length);
function turnTo(i) {                       // bring bough i to the front
  let want = -ringAngle(i);
  while (want - T3.rot > Math.PI) want -= 2 * Math.PI;
  while (want - T3.rot < -Math.PI) want += 2 * Math.PI;
  T3.target = want;
}

function select3d(part) {
  T3.touched = true;
  T3.sel = part;
  if (part.startsWith('leaf:')) turnTo(+part.split(':')[1]);
  document.querySelectorAll('.t3-chip').forEach(b => b.classList.toggle('on', b.dataset.t3 === part || (part.startsWith('root') && b.dataset.t3 === 'roots')));
  info3d();
  draw3d();
}

/* one leafy bough: overlapping leaf clumps with shade below and light from the top-left */
function bough(it, on) {
  const {l, i, x, y, r, depth} = it, f = FOLIAGE[l.health] || FOLIAGE.HEALTHY, st = STATUS[l.health] || STATUS.HEALTHY;
  const rand = rnd(i * 13 + 7), thin = l.health === 'ROTTEN', n = thin ? 10 : 17;
  const puffs = Array.from({length: n}, () => { const a = rand() * 6.283, d = Math.sqrt(rand()) * r * .78; return {x: x + Math.cos(a) * d, y: y + Math.sin(a) * d * .72, r: r * (.34 + rand() * .22), mix: rand()}; });
  let s = '';
  if (thin) {                                       // bare twigs show through a thinning bough
    for (let j = 0; j < 4; j++) { const a = -1.9 + j * .55; s += `<path d="M${x.toFixed(1)} ${(y + r * .4).toFixed(1)} q ${(Math.cos(a) * r * .5).toFixed(1)} ${(Math.sin(a) * r * .5).toFixed(1)} ${(Math.cos(a) * r).toFixed(1)} ${(Math.sin(a) * r * .85).toFixed(1)}" fill="none" stroke="${BARK.dark}" stroke-width="1.6" stroke-linecap="round"/>`; }
  }
  puffs.forEach(p => { s += `<circle cx="${(p.x + 2).toFixed(1)}" cy="${(p.y + 4).toFixed(1)}" r="${p.r.toFixed(1)}" fill="${f.dark}"/>`; });
  puffs.forEach(p => {
    const col = l.health === 'WILTING' && p.mix > .62 ? FOLIAGE.HEALTHY.mid : f.mid;      // yellowing boughs keep some green
    s += `<circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="${(p.r * .92).toFixed(1)}" fill="${col}"/>`;
  });
  puffs.filter(p => p.x < x + r * .25 && p.y < y + r * .15).forEach(p => {
    s += `<circle cx="${(p.x - p.r * .22).toFixed(1)}" cy="${(p.y - p.r * .26).toFixed(1)}" r="${(p.r * .55).toFixed(1)}" fill="${f.light}" opacity=".75"/>`;
  });
  for (let j = 0; j < 9; j++) {                     // single leaves at the edge
    const a = rand() * 6.283, d = r * (.85 + rand() * .22), lx = x + Math.cos(a) * d, ly = y + Math.sin(a) * d * .72;
    s += `<ellipse cx="${lx.toFixed(1)}" cy="${ly.toFixed(1)}" rx="${(r * .13).toFixed(1)}" ry="${(r * .065).toFixed(1)}" transform="rotate(${(a * 57.3).toFixed(0)} ${lx.toFixed(1)} ${ly.toFixed(1)})" fill="${f.leaf}"/>`;
  }
  let falling = '';
  if (thin) {                                       // leaves drifting down: money slipping away
    for (let j = 0; j < 4; j++) { const fx = x - r * .7 + rand() * r * 1.4, fy = y + r * (.9 + rand() * .9); falling += `<ellipse class="t3-fall" style="animation-delay:${(-j * .9).toFixed(1)}s" cx="${fx.toFixed(1)}" cy="${fy.toFixed(1)}" rx="${(r * .12).toFixed(1)}" ry="${(r * .06).toFixed(1)}" transform="rotate(${(rand() * 180).toFixed(0)} ${fx.toFixed(1)} ${fy.toFixed(1)})" fill="${f.light}"/>`; }
  }
  const badge = `<circle cx="${(x + r * .78).toFixed(1)}" cy="${(y - r * .72).toFixed(1)}" r="${(7 + depth * 3).toFixed(1)}" fill="${st.c}" stroke="#fff" stroke-width="2"/>${t(x + r * .78, y - r * .72 + 4, st.icon, {anchor: 'middle', size: 10 + depth * 2, fill: '#fff', weight: 700})}`;
  return `<g data-part="leaf:${i}" class="t3-part t3-bough${on ? ' sel' : ''}" style="animation-delay:${(-i * .7).toFixed(1)}s;transform-origin:${x.toFixed(0)}px ${(y + r).toFixed(0)}px" opacity="${(.62 + depth * .38).toFixed(2)}"${on ? ' filter="url(#t3glow)"' : ''}>${s}${falling}${badge}</g>`;
}

function draw3d() {
  const svg = document.getElementById('t3svg'), tr = T3.tr;
  if (!svg || !tr) return;
  const cx = 380, top = 428, rx = 316, ry = 74, wall = 92, fork = 268;   // platform top ellipse at y=top; trunk forks at y=fork
  const sel = T3.sel;
  let g = `<defs>
    <linearGradient id="t3bark" x1="0" x2="1"><stop offset="0" stop-color="${BARK.dark}"/><stop offset=".38" stop-color="${BARK.light}"/><stop offset=".62" stop-color="${BARK.mid}"/><stop offset="1" stop-color="${BARK.dark}"/></linearGradient>
    <linearGradient id="t3wall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9b7b52"/><stop offset=".5" stop-color="#7d6140"/><stop offset="1" stop-color="#5c452b"/></linearGradient>
    <radialGradient id="t3top" cx=".42" cy=".35" r=".8"><stop offset="0" stop-color="#cfe6b8"/><stop offset=".7" stop-color="#9cc584"/><stop offset="1" stop-color="#7fae6c"/></radialGradient>
    <clipPath id="t3cut"><path d="M${cx - rx} ${top} A${rx} ${ry} 0 0 0 ${cx + rx} ${top} L${cx + rx} ${top + wall} A${rx} ${ry} 0 0 1 ${cx - rx} ${top + wall} Z"/></clipPath>
    <filter id="t3glow" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="0" stdDeviation="6" flood-color="#0018a8" flood-opacity=".6"/></filter></defs>`;
  const wx = {CALM: ['☀', 'Calm'], BREEZY: ['☁', 'Breezy'], WINDY: ['≋', 'Windy'], STORM: ['⛈', 'Storm']}[tr.weather?.type] || ['☀', 'Calm'];
  g += t(744, 28, wx[0] + ' ' + wx[1], {anchor: 'end', size: 13, fill: C.muted});

  // ---- ground: soil wall with strata and pebbles, then the grassy top
  const soil = tr.soil || {richness: 0, layers: 1}, rs = rnd(5);
  g += `<g data-part="soil" class="t3-part${sel === 'soil' ? ' sel' : ''}"${sel === 'soil' ? ' filter="url(#t3glow)"' : ''}><path d="M${cx - rx} ${top} A${rx} ${ry} 0 0 0 ${cx + rx} ${top} L${cx + rx} ${top + wall} A${rx} ${ry} 0 0 1 ${cx - rx} ${top + wall} Z" fill="url(#t3wall)"/>
    <g clip-path="url(#t3cut)">${Array.from({length: Math.max(2, Math.min(4, (soil.layers || 1) + 1))}, (_, i) => `<path d="M${cx - rx} ${top + 24 + i * 20} A${rx} ${ry} 0 0 0 ${cx + rx} ${top + 24 + i * 20}" fill="none" stroke="#3f2f1c" stroke-opacity=".28" stroke-width="2" stroke-dasharray="3 7"/>`).join('')}
    ${Array.from({length: 26}, () => { const px = cx - rx + rs() * rx * 2, py = top + 20 + rs() * (wall + ry - 30); return `<ellipse cx="${px.toFixed(0)}" cy="${py.toFixed(0)}" rx="${(2 + rs() * 4).toFixed(1)}" ry="${(1.5 + rs() * 2.5).toFixed(1)}" fill="#c9b596" opacity=".45"/>`; }).join('')}</g></g>`;
  g += `<ellipse cx="${cx}" cy="${top}" rx="${rx}" ry="${ry}" fill="url(#t3top)"/>`;
  const rim = x => top + ry * Math.sqrt(Math.max(0, 1 - ((x - cx) / rx) ** 2));             // front edge of the grass
  let turf = '';
  for (let i = 0; i <= 46; i++) { const x = cx - rx + 8 + i * (rx * 2 - 16) / 46, y = rim(x); turf += `<path d="M${(x - 5).toFixed(1)} ${(y - 2).toFixed(1)} q 5 ${(7 + rs() * 6).toFixed(1)} 10 0" fill="#7fae6c"/>`; }
  const rg = rnd(11);
  for (let i = 0; i < 70; i++) {
    const a = rg() * 6.283, d = Math.sqrt(rg()), x = cx + Math.cos(a) * d * (rx - 14), y = top + Math.sin(a) * d * (ry - 8), h = 5 + rg() * 6;
    turf += `<path d="M${x.toFixed(1)} ${y.toFixed(1)} l -2 ${(-h).toFixed(1)} M${x.toFixed(1)} ${y.toFixed(1)} l 2.5 ${(-h * .8).toFixed(1)}" stroke="${rg() > .5 ? '#5e9a57' : '#86bb73'}" stroke-width="1.3" stroke-linecap="round" fill="none"/>`;
    if (i % 12 === 0) turf += `<circle cx="${(x + 6).toFixed(1)}" cy="${(y - 3).toFixed(1)}" r="2.2" fill="${i % 24 ? '#fff6c9' : '#f6c9d8'}"/>`;
  }
  g += turf;
  // one flower per finished learning mission, planted around the trunk
  const fl = typeof learnedCount === 'function' ? learnedCount() : 0, rf = rnd(77);
  for (let i = 0; i < fl; i++) {
    const a = -2.6 + i * .95 + rf() * .3, fx = cx + Math.cos(a) * (120 + rf() * 60), fy = top + 18 + Math.sin(a) * 30 + rf() * 10, col = ['#f2bfd0', '#fff1a8', '#c9d3ff', '#ffd2b0', '#e3c9ff', '#bfe8d2'][i % 6];
    g += `<g><title>Learning mission finished</title><path d="M${fx} ${fy} l0 -12" stroke="#4f8a4a" stroke-width="2"/>${[0, 72, 144, 216, 288].map(d => `<circle cx="${(fx + Math.cos(d / 57.3) * 4).toFixed(1)}" cy="${(fy - 14 + Math.sin(d / 57.3) * 4).toFixed(1)}" r="3.4" fill="${col}"/>`).join('')}<circle cx="${fx}" cy="${fy - 14}" r="2.4" fill="#f0b429"/></g>`;
  }
  g += `<ellipse cx="${cx + 26}" cy="${top + 8}" rx="150" ry="26" fill="#1f3d22" opacity=".2"/>`;   // shadow of the crown

  // ---- roots in the cut: one main root per savings pot, with rootlets
  const roots = tr.roots || [], m = roots.length;
  roots.forEach((r, i) => {
    const x1 = cx + (m === 1 ? 0 : (i / (m - 1) - .5) * 440), y1 = rim(x1) + 16 + Math.min(1, r.depth || 0) * (wall - 40);
    const col = r.status === 'NEEDS_CARE' || (r.health || 0) < .4 ? C.watch : C.ok, id = 'root:' + i, on = sel === id;
    const hasT = r.target > 1, pct = hasT ? Math.round(Math.min(1, r.balance / r.target) * 100) + '%' : 'not set up';
    const p0 = [cx + (x1 - cx) * .05, rim(cx) - 4], pc = [cx + (x1 - cx) * .35, y1 + 4], p1 = [x1, y1], w = 6 + (r.thickness || 0) * 9;
    const rr = rnd(i + 31);
    let lets = '';
    for (let j = 0; j < 3; j++) { const u = .45 + j * .2, bx = p0[0] + (p1[0] - p0[0]) * u, by = p0[1] + (p1[1] - p0[1]) * u + 8; lets += limb([bx, by], [bx + (rr() - .5) * 30, by + 12], [bx + (rr() - .5) * 46, by + 18 + rr() * 12], 2.6, .6, '#3a2b1b'); }
    g += `<g data-part="${id}" class="t3-part${on ? ' sel' : ''}"${on ? ' filter="url(#t3glow)"' : ''}><g clip-path="url(#t3cut)">${limb(p0, pc, p1, w, 2, '#3a2b1b')}${lets}</g>
      <circle cx="${x1}" cy="${y1}" r="7" fill="${col}" stroke="#fff" stroke-width="2"/>
      ${t(x1 + (x1 < cx ? -12 : 12), y1 + 4, `${r.label.replace(' roots', '')} · ${pct}`, {anchor: x1 < cx ? 'end' : 'start', size: 11, fill: '#fff', weight: 700, halo: '#5e4a31'})}</g>`;
  });
  g += t(cx, rim(cx) + wall - 10, `Soil · learning ${Math.round((soil.richness || 0) * 100)}/100`, {anchor: 'middle', size: 12, fill: '#fff', weight: 700, halo: '#5e4a31'});

  // ---- crown: boughs on a ring around the trunk, two heights
  const leaves = T3.leaves, R = 236, crownY = [176, 104];
  const items = leaves.map((l, i) => {
    const a = ringAngle(i) + T3.rot, z = Math.cos(a), x = cx + Math.sin(a) * R, y = crownY[i % 2] + z * 44;
    const depth = (z + 1) / 2, r = (26 + (l.size || .3) * 26) * (.7 + .4 * depth);
    return {l, i, x, y, z, r, depth, a};
  });
  const tk = tr.trunk || {thickness: .3, cracks: 0}, tw = 26 + (tk.thickness || 0) * 34;
  const limbFor = it => {
    const start = [cx + Math.sin(it.a) * tw * .22, fork + 10 - (it.i % 2) * 14], endp = [it.x, it.y + it.r * .35];
    const ctrl = [cx + (it.x - cx) * .45, Math.min(start[1], endp[1]) - 6 + (it.i % 2 ? 26 : 44)];
    const shade = it.z < 0 ? BARK.dark : BARK.mid;
    return limb(start, ctrl, endp, 7 + it.depth * 6, 2, shade, .75 + it.depth * .25)
      + limb([(ctrl[0] + endp[0]) / 2, (ctrl[1] + endp[1]) / 2 - 2], [endp[0] - 10, endp[1] - it.r * .7], [endp[0] + (it.x < cx ? -1 : 1) * it.r * .5, endp[1] - it.r * .9], 3, 1, shade, .7);
  };
  const label = it => {
    const on = sel === 'leaf:' + it.i;
    if (!(it.z > .2 || on)) return '';
    const ly = Math.abs(it.x - cx) < 80 ? it.y - it.r - 24 : it.y + it.r + 18;
    return t(it.x, ly, it.l.label, {anchor: 'middle', weight: 700, halo: '#f0f6f7'}) + t(it.x, ly + 15, k(it.l.monthlyAmount) + '/mo', {anchor: 'middle', size: 11, fill: C.muted, halo: '#f0f6f7'});
  };
  const rc = rnd(3);                                  // soft inner canopy so the boughs read as one crown
  g += `<g opacity=".5">${Array.from({length: 14}, () => `<circle cx="${(cx - 110 + rc() * 220).toFixed(0)}" cy="${(120 + rc() * 105).toFixed(0)}" r="${(30 + rc() * 26).toFixed(0)}" fill="#2f6f4f"/>`).join('')}</g>`;
  const back = items.filter(it => it.z < 0).sort((a, b) => a.z - b.z), front = items.filter(it => it.z >= 0).sort((a, b) => a.z - b.z);
  back.forEach(it => { g += limbFor(it) + bough(it, sel === 'leaf:' + it.i) + label(it); });

  // ---- trunk: tapered, with a root flare, bark lines, a knot and cracks for risks
  const b = top + 6;
  g += `<g data-part="trunk" class="t3-part${sel === 'trunk' ? ' sel' : ''}"${sel === 'trunk' ? ' filter="url(#t3glow)"' : ''}>
    ${limb([cx - tw * .2, b - 6], [cx - tw * 1.2, b - 4], [cx - tw * 2.1, b + 8], tw * .5, 2, BARK.dark)}${limb([cx + tw * .2, b - 6], [cx + tw * 1.3, b - 2], [cx + tw * 2.2, b + 6], tw * .5, 2, BARK.dark)}${limb([cx, b - 4], [cx + tw * .5, b + 10], [cx + tw * .9, b + 22], tw * .45, 2, BARK.dark)}
    <path d="M${cx - tw * .95} ${b} C ${cx - tw * .5} ${b - 34}, ${cx - tw * .46} ${fork + 70}, ${cx - tw * .34} ${fork} Q ${cx} ${fork - 12} ${cx + tw * .34} ${fork} C ${cx + tw * .46} ${fork + 70}, ${cx + tw * .5} ${b - 34}, ${cx + tw * .95} ${b} Q ${cx} ${b + 12} ${cx - tw * .95} ${b} Z" fill="url(#t3bark)"/>
    ${[-.28, -.12, .05, .2, .31].map((o, i) => `<path d="M${cx + tw * o} ${fork + 8 + i * 5} q ${3 - i} 40 ${-2 + i} 78 t ${i - 2} ${top - fork - 100}" fill="none" stroke="${i % 2 ? BARK.dark : '#2c2117'}" stroke-opacity=".38" stroke-width="1.4" stroke-linecap="round"/>`).join('')}
    <ellipse cx="${cx - tw * .1}" cy="${fork + 62}" rx="5" ry="7" fill="${BARK.dark}" opacity=".55"/><ellipse cx="${cx - tw * .1}" cy="${fork + 62}" rx="2.2" ry="3.4" fill="#231a12" opacity=".7"/>
    ${Array.from({length: Math.min(4, tk.cracks || 0)}, (_, i) => `<path d="M${cx + 2 + i * 4} ${fork + 92 + i * 16} l5 7 l-5 6 l5 7 l-4 6" fill="none" stroke="#1d150e" stroke-width="2" stroke-linejoin="round"/>`).join('')}</g>`;
  (tr.branches || []).slice(0, 2).forEach((br, i) => {
    const y = 344 + i * 30, len = 74 + (br.length || 0) * 60, x1 = cx - tw * .4 - len, id = 'branch:' + i, on = sel === id;
    g += `<g data-part="${id}" class="t3-part${on ? ' sel' : ''}"${on ? ' filter="url(#t3glow)"' : ''}>${limb([cx - tw * .36, y], [cx - tw * .4 - len * .55, y + 2], [x1, y - 22], 8, 2.5, BARK.mid)}
      ${br.fruit ? `<circle cx="${x1}" cy="${y - 16}" r="9" fill="#c8402e"/><circle cx="${x1 - 3}" cy="${y - 19}" r="3" fill="#fff" opacity=".45"/>` : br.blossom ? `<circle cx="${x1}" cy="${y - 22}" r="8" fill="#f2bfd0"/><circle cx="${x1}" cy="${y - 22}" r="3" fill="#f6e39a"/>` : `<ellipse cx="${x1 - 5}" cy="${y - 26}" rx="9" ry="4.5" transform="rotate(-30 ${x1 - 5} ${y - 26})" fill="#6cc393"/><ellipse cx="${x1 + 5}" cy="${y - 28}" rx="8" ry="4" transform="rotate(25 ${x1 + 5} ${y - 28})" fill="#3da06f"/>`}
      ${t(x1 - 16, y - 18, `${br.name} · ${Math.round((br.length || 0) * 100)}%`, {anchor: 'end', size: 11, fill: C.muted, halo: '#f0f6f7'})}</g>`;
  });
  front.forEach(it => { g += limbFor(it) + bough(it, sel === 'leaf:' + it.i) + label(it); });
  svg.innerHTML = g;
}

function bar(value, max, color, label) {
  const w = max > 0 ? Math.max(2, Math.min(100, value / max * 100)) : 0;
  return `<div class="t3-bar"><span>${esc(label)}</span><div><i style="width:${w}%;background:${color}"></i></div><b>${k(value)}</b></div>`;
}
function info3d() {
  const el = document.getElementById('t3info'), tr = T3.tr;
  if (!el || !tr) return;
  const sel = T3.sel || '';
  const [kind, idx] = sel.split(':');
  let h = '';
  if (kind === 'leaf') {
    const l = T3.leaves[+idx], st = STATUS[l.health] || STATUS.HEALTHY;
    const ratio = l.peerAverage > 0 ? l.monthlyAmount / l.peerAverage : null;
    const look = {HEALTHY: 'A lush bough.', WILTING: 'This bough is yellowing.', ROTTEN: 'This bough is losing leaves.'}[l.health] || '';
    h = `<p class="eyebrow">SPENDING · LEAVES</p><h3>${esc(l.label)}</h3><div class="t3-big">${k(l.monthlyAmount)}<small>/month</small></div>
      <span class="t3-status" style="background:${st.c}">${st.icon} ${st.word}</span>
      ${bar(l.monthlyAmount, Math.max(l.monthlyAmount, l.peerAverage || 0), st.c, 'You')}${l.peerAverage ? bar(l.peerAverage, Math.max(l.monthlyAmount, l.peerAverage), C.base, 'People like you') : ''}
      <p class="sub">${look} ${ratio && ratio >= 1.2 ? `${ratio.toFixed(1)}× what households with your income spend.` : 'Close to what households with your income spend.'}${l.trendPct ? ` ${l.trendPct > 0 ? 'Up' : 'Down'} ${Math.round(Math.abs(l.trendPct) * 100)}% recently.` : ''}</p>
      ${l.health !== 'HEALTHY' ? '<a class="button" href="#actions">See how to bring it down →</a>' : ''}`;
  } else if (kind === 'root') {
    const r = (tr.roots || [])[+idx], hasT = r.target > 1, col = r.status === 'NEEDS_CARE' || (r.health || 0) < .4 ? C.watch : C.ok;
    h = `<p class="eyebrow">SAVINGS · ROOTS</p><h3>${esc(r.label.replace(' roots', ' savings'))}</h3><div class="t3-big">${k(r.balance)}</div>
      ${hasT ? bar(r.balance, r.target, col, 'Saved') + `<p class="sub">${Math.round(Math.min(1, r.balance / r.target) * 100)}% of the ${k(r.target)} target. Deeper roots hold the tree in a storm.</p>` : '<p class="sub">Not set up yet.</p>'}
      ${hasT && r.balance / r.target < .5 ? '<a class="button" href="#actions">Build it up →</a>' : ''}`;
  } else if (kind === 'roots') {
    h = `<p class="eyebrow">SAVINGS · ROOTS</p><h3>Your savings pots</h3>${(tr.roots || []).map(r => bar(r.balance, r.target > 1 ? r.target : Math.max(1, r.balance), r.target > 1 && r.balance / r.target < .5 ? C.watch : C.ok, r.label.replace(' roots', ''))).join('')}<p class="sub">Deeper roots: fuller pots. Tap a root in the soil for one pot.</p>`;
  } else if (kind === 'trunk') {
    const tk = tr.trunk || {};
    h = `<p class="eyebrow">INVESTING · TRUNK</p><h3>Your investments</h3><div class="t3-big">${k(tk.invested || 0)}</div>
      <span class="t3-status" style="background:${(tk.cracks || 0) ? C.watch : C.ok}">${(tk.cracks || 0) ? `! ${tk.cracks} crack${tk.cracks > 1 ? 's' : ''}: risk${tk.cracks > 1 ? 's' : ''} to look at` : '✓ steady'}</span>
      ${tk.idleCash ? bar(tk.idleCash, (tk.invested || 0) + tk.idleCash, C.watch, 'Idle cash') : ''}<p class="sub">A thicker trunk means more invested for the long run. Cracks in the bark show where too much depends on one thing.</p><a class="button" href="#future">See your future →</a>`;
  } else if (kind === 'soil') {
    const s = tr.soil || {};
    h = `<p class="eyebrow">LEARNING · SOIL</p><h3>Your money confidence</h3><div class="t3-big">${Math.round((s.richness || 0) * 100)}<small>/100</small></div>
      ${bar((s.richness || 0) * 100, 100, C.soilHi, 'Confidence')}<p class="sub">${typeof learnedCount === 'function' ? learnedCount() : 0} learning missions finished: each one planted a flower. Richer soil helps every part grow.</p><a class="button" href="#learn">Learn & grow →</a>`;
  } else if (kind === 'branch') {
    const b = (tr.branches || [])[+idx];
    h = `<p class="eyebrow">LIFE PROJECT · BRANCH</p><h3>${esc(b.name)}</h3><div class="t3-big">${Math.round((b.length || 0) * 100)}<small>% there</small></div>
      <p class="sub">${esc(b.detail || '')} It blossoms at half way and bears fruit when funded.</p><a class="button" href="#projects">Plan your projects →</a>`;
  } else {
    const bad = (T3.leaves || []).filter(l => l.health !== 'HEALTHY').length;
    h = `<p class="eyebrow">YOUR WEALTH TREE</p><h3>${esc(tr.headline || '')}</h3>
      <ul class="t3-key"><li><b>Leaves</b> what you spend, one bough per category</li><li><b>Trunk</b> what you invest</li><li><b>Roots</b> your savings, in the soil</li><li><b>Soil</b> your money confidence</li></ul>
      <p class="sub">${bad ? `${bad} bough${bad > 1 ? 's are' : ' is'} yellowing or losing leaves. ` : ''}Tap any part of the tree, or drag to turn it.</p>`;
  }
  el.innerHTML = h;
}

document.addEventListener('click', e => {
  const b = e.target.closest('[data-t3]');
  if (!b) return;
  const what = b.dataset.t3;
  T3.touched = true;
  if (what === 'left' || what === 'right') {
    const step = 2 * Math.PI / Math.max(1, (T3.leaves || []).length);
    T3.target = (T3.target ?? T3.rot) + (what === 'left' ? step : -step);
    return;
  }
  select3d(what);
});
