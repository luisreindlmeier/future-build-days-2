/* =====================================================================
   APP — state, rendering and events. Reads CFG/PERSONAS (config.js),
   judges with engine.js, and lets Claude think via ai.js.
   ===================================================================== */

/* ---------- state ---------- */
let user = SCAN;                 // the score — a constant for now
let projects = loadProjects();

/* When the scan backend exists: set SCORE_API_URL in config.js and this
   replaces the constant with the fetched score. Same JSON shape. */
async function loadScore() {
  const c = await loadCustomer();                // input.txt → real customer (see customer.js)
  if (c) { user = c; render(); return; }
  if (!SCORE_API_URL) return;
  try {
    const r = await fetch(SCORE_API_URL);
    if (r.ok) { user = await r.json(); render(); }
  } catch (e) { console.warn("Score API unreachable — using the constant.", e); }
}

function loadProjects() {
  try {
    const saved = JSON.parse(localStorage.getItem("kairos-projects") || "null");
    if (saved) return saved;
  } catch (e) {}
  return structuredClone(DEFAULT_PROJECTS);
}
function persist() {
  try { localStorage.setItem("kairos-projects", JSON.stringify(projects)); } catch (e) {}
}

const $ = (s, r = document) => r.querySelector(s);

/* ---------- small view helpers ---------- */
function dot(kind) {
  const map = { ok: ["var(--good)", "✓"], warn: ["var(--warn)", "!"], bad: ["var(--bad)", "✕"], rule: ["#5A6377", "✕"] };
  const [bg, ch] = map[kind] || map.ok;
  return `<span class="dot" style="background:${bg}">${ch}</span>`;
}
function chip(v) {
  if (!v) return `<span class="chip none">Not checked yet</span>`;
  return v === "good" ? `<span class="chip good">Good idea</span>`
       : v === "warn" ? `<span class="chip warn">Adjust the plan</span>`
       : `<span class="chip bad">Not yet</span>`;
}

/* ---------- "describe your plan" box (every project type) ---------- */
function ideaBox(p, i) {
  const what = p.type === "business" ? "business idea" : "plan";
  return `<label for="idea${i}" class="idea-label">Describe your ${what} in your own words — Kairos AI estimates the costs and whether you need a loan</label>
    <div class="idea-wrap">
      <textarea id="idea${i}" class="idea" data-idea="${i}" rows="3" maxlength="1500"
        placeholder="${esc(PROJECT_TYPES[p.type].ask || "")}">${esc(p.idea || "")}</textarea>
      <button class="idea-clear" data-clearidea="${i}" type="button" aria-label="Clear the description" ${p.idea ? "" : "hidden"}>✕ Clear</button>
    </div>`;
}

/* ---------- render ---------- */
/* The AI plan is the verdict now (no sliders): map it to good / warn / bad. */
const verdictOf = p => p.plan ? ({ good: "good", adjust: "warn", not_yet: "bad" }[p.plan.verdict] || "warn") : null;
function readyMonth(p) {                       // "Nov 2027" → months from today (or null)
  if ((p.plan || {}).ready === "now") return 0;
  const m = String((p.plan || {}).ready || "").match(/([A-Za-z]{3})\w*\s+(\d{4})/);
  if (!m) return null;
  const idx = MO.indexOf(m[1][0].toUpperCase() + m[1].slice(1, 3).toLowerCase());
  return idx < 0 ? null : Math.max(0, +m[2] * 12 + idx - CFG.startYM);
}

function render() {
  const planned = projects.filter(p => p.plan);                 // only AI-checked plans have real numbers
  const sim = simulate(user, planned);
  const judged = projects.map(p => ({ v: verdictOf(p), fitM: p.plan ? readyMonth(p) : null }));

  renderScan(judged);
  renderProjects(judged);
  renderPortfolio(sim, judged);
  renderAdvisor(judged);
  persist();
}

function renderScan(judged) {
  const counts = { good: 0, warn: 0, bad: 0 };
  judged.forEach(j => { if (j.v) counts[j.v]++; });
  $("#statRow").innerHTML = `
    <div><b>${projects.length}</b><span>projects</span></div>
    <div><b style="color:var(--good)">${counts.good}</b><span>good idea</span></div>
    <div><b style="color:var(--warn)">${counts.warn}</b><span>adjust</span></div>
    <div><b style="color:var(--bad)">${counts.bad}</b><span>not yet</span></div>`;
  const pr = user.profile;
  $("#scanChip").textContent = "Scan: " + user.name + (pr ? ` · ${pr.age} · ${eur(user.income)}/month` : " · demo");
  $("#vitalRow").innerHTML = Object.entries(user.vitals)
    .map(([k, v]) => `<span class="vital">${k} <i>· ${word(v)}</i></span>`).join("")
    + `<span class="vital" style="background:#15203A;color:#fff">${user.level}</span>`;
  const gate = $("#gateNote");
  gate.hidden = !foundationBlocked(user);
  if (!gate.hidden)
    gate.innerHTML = `<b>Foundation first.</b> ${user.name}'s base is fragile, so Kairos blocks every financing path and shows the two moves that unlock them: a 1-month cushion (${eur(user.costs)}) and clearing expensive debt.`;
}

function renderProjects(judged) {
  if (!projects.length) {
    $("#projects").innerHTML = `<div class="card empty">
      <b>No plans yet</b>
      <p class="sub">Add your first life project — a car, a home, a trip, a business… — with the button below. Describe it in your own words and Kairos AI estimates what it costs and whether you need a loan.</p></div>`;
    return;
  }
  $("#projects").innerHTML = projects.map((p, i) => {
    const j = judged[i];
    return `<div class="card">
      <div class="proj-head">
        <div class="proj-title"><span class="icon-box">${PROJECT_TYPES[p.type].icon}</span>${p.name}</div>
        <div style="display:flex;align-items:center;gap:8px">${chip(j.v)}
          <button class="del" data-del="${i}" type="button" aria-label="Remove project">✕</button></div>
      </div>
      <div class="label">Your plan</div>
      ${ideaBox(p, i)}
      <button class="adv-btn" data-ai="${i}" type="button" style="margin-top:4px">${p.plan ? "Ask Kairos AI again — update my plan" : "Ask Kairos AI — check my plan"}</button>
      <div id="ai${i}">${p.plan ? planHTML(p, i) : ""}</div>
      <p class="sub db-help"><b>How Deutsche Bank helps:</b> ${PROJECT_TYPES[p.type].db}</p>
    </div>`;
  }).join("");
}

function renderPortfolio(sim, judged) {
  const planned = projects.filter(p => p.plan);
  const monthlyNeed = planned.reduce((s, p) => s + goalAmount(user, p) / Math.max(1, p.targetM), 0);
  const car = planned.find(p => p.type === "car" && p.plan.loan.payment > 0);
  let cross = "";
  if (car && !foundationBlocked(user)) {
    const drop = car.plan.loan.payment * 12 / (CFG.rates.mortgage + CFG.rates.mortgageRepay);
    cross = `<div class="reason"><span class="dot" style="background:var(--warn)">!</span><span>The car loan lowers what a bank lends you for a home by about <b>${eur(drop)}</b>. Paying cash protects your mortgage capacity.</span></div>`;
  }
  $("#portfolio").innerHTML = `
    <div class="reason"><span class="dot" style="background:var(--good)">✓</span><span>Safety cushion: <b>${eur(sim.cushion)}</b> of ${eur(sim.cushionTarget)}${sim.cushion >= sim.cushionTarget ? " — full, every euro goes to projects." : " — fills first, 30% of each month."}</span></div>
    <div class="reason"><span class="dot" style="background:${monthlyNeed > user.capacity ? "var(--warn)" : "var(--good)"}">${monthlyNeed > user.capacity ? "!" : "✓"}</span><span>Your projects want about <b>${eur(monthlyNeed)} a month</b> to hit every date; you can put aside <b>${eur(user.capacity)}</b>. Kairos funds the nearest first${monthlyNeed > user.capacity ? " — moving one date later is the simplest fix." : "."}</span></div>
    ${cross}`;
}

/* ---------- advisor: donut of the user's own plans ----------
   One slice per project TYPE the user added (two trips = one "trip" slice),
   sized by the money each needs saved up front (goalAmount). Colors are
   fixed per type, so a slice keeps its color when others are added/removed. */
const TYPE_COLORS = { car: "#2a78d6", home: "#eb6834", trip: "#1baf7a", business: "#eda100",
                      family: "#e87ba4", studies: "#008300", sabbatical: "#6250d6" };

function donutArc(cx, cy, r0, r1, a0, a1) {
  const pt = (r, a) => [cx + r * Math.sin(a), cy - r * Math.cos(a)];
  const big = a1 - a0 > Math.PI ? 1 : 0;
  const [x0, y0] = pt(r1, a0), [x1, y1] = pt(r1, a1), [x2, y2] = pt(r0, a1), [x3, y3] = pt(r0, a0);
  return `M${x0} ${y0}A${r1} ${r1} 0 ${big} 1 ${x1} ${y1}L${x2} ${y2}A${r0} ${r0} 0 ${big} 0 ${x3} ${y3}Z`;
}

function renderAdvisor(judged) {
  // group the user's projects by type, in the catalog's fixed order
  const groups = Object.keys(PROJECT_TYPES).map(type => {
    const items = projects.filter(p => p.type === type && p.plan);
    return { type, items, amount: items.reduce((s, p) => s + goalAmount(user, p), 0) };
  }).filter(g => g.items.length && g.amount > 0);
  const total = groups.reduce((s, g) => s + g.amount, 0);

  if (!groups.length) {
    $("#advBody").innerHTML = `<p class="sub" style="font-size:13.5px">No plans yet. Add a project with <b>+</b> and it appears here.</p>`;
    return;
  }

  const R1 = 90, R0 = 58, C = 100;
  let a = 0;
  const slices = groups.map(g => {
    const share = g.amount / total;
    const a1 = a + share * 2 * Math.PI;
    // a single slice is a full ring: draw it as two halves so the arc is valid
    const d = groups.length === 1
      ? donutArc(C, C, R0, R1, 0, Math.PI) + donutArc(C, C, R0, R1, Math.PI, 2 * Math.PI)
      : donutArc(C, C, R0, R1, a, a1);
    a = a1;
    return { ...g, share, d };
  });
  const label = g => PROJECT_TYPES[g.type].label + (g.items.length > 1 ? ` (${g.items.length})` : "");
  const pct = s => (s < 0.01 ? "<1" : Math.round(s * 100)) + "%";

  $("#advBody").innerHTML = `
    <div class="donut-wrap">
      <div class="donut-box">
        <svg viewBox="0 0 200 200" class="donut" role="img" aria-label="Share of savings needed per type of plan">
          ${slices.map((g, i) => `<path d="${g.d}" fill="${TYPE_COLORS[g.type]}" data-slice="${i}"
              stroke="#fff" stroke-width="2" stroke-linejoin="round"></path>`).join("")}
          <text x="100" y="96" text-anchor="middle" class="donut-total">${eur(total)}</text>
          <text x="100" y="116" text-anchor="middle" class="donut-cap">to save in total</text>
        </svg>
        <div class="donut-tip" hidden></div>
      </div>
      <ul class="donut-legend">
        ${slices.map((g, i) => `<li data-slice="${i}">
          <span class="sw" style="background:${TYPE_COLORS[g.type]}"></span>
          <span class="nm">${PROJECT_TYPES[g.type].icon} ${label(g)}</span>
          <b class="num">${eur(g.amount)}</b><span class="pc">${pct(g.share)}</span></li>`).join("")}
      </ul>
    </div>
    <div class="label">Mandate moments</div>
    <table>
      <tr><th>Project</th><th>Verdict</th><th>Turns healthy</th></tr>
      ${projects.map((p, i) => `<tr><td>${p.name}</td>
        <td>${judged[i].v === "good" ? "Good idea" : judged[i].v === "warn" ? "Adjust" : judged[i].v === "bad" ? "Not yet" : "Not checked"}</td>
        <td class="num">${judged[i].fitM == null ? "—" : (judged[i].fitM === 0 ? "Now" : "~" + yOf(judged[i].fitM))}</td></tr>`).join("")}
    </table>
    <p class="sub" style="margin-top:10px;font-size:12.5px">Sort clients by their next mandate moment: that quarter is when a right-time loan or mandate conversation is both winnable and safe.</p>`;

  // hover: slice or legend row → highlight + tooltip with the projects inside
  const body = $("#advBody"), tip = $(".donut-tip", body), box = $(".donut-box", body);
  const focus = i => {
    body.querySelectorAll("[data-slice]").forEach(el => el.classList.toggle("dim", i !== null && +el.dataset.slice !== i));
    if (i === null) { tip.hidden = true; return; }
    const g = slices[i];
    tip.innerHTML = `<b>${label(g)} · ${eur(g.amount)} (${pct(g.share)})</b>`
      + g.items.map(p => `<div>${p.name}: ${eur(goalAmount(user, p))}</div>`).join("");
    tip.hidden = false;
  };
  body.querySelectorAll("[data-slice]").forEach(el => {
    el.addEventListener("mouseenter", () => focus(+el.dataset.slice));
    el.addEventListener("mouseleave", () => focus(null));
  });
  box.addEventListener("mousemove", e => {
    const r = box.getBoundingClientRect();
    tip.style.left = (e.clientX - r.left + 12) + "px"; tip.style.top = (e.clientY - r.top + 12) + "px";
  });
}

/* ---------- events ---------- */
document.addEventListener("input", e => {
  const t = e.target;
  if (t.dataset && t.dataset.idea !== undefined) {   // typing the idea: save only, no re-render (keeps the cursor)
    projects[+t.dataset.idea].idea = t.value; persist();
    t.parentElement.querySelector(".idea-clear").hidden = !t.value;   // show "Clear" only when there is text
    return;
  }
});

document.addEventListener("click", e => {
  const t = e.target.closest("button");
  if (!t) return;

  if (t.dataset.del !== undefined) { projects.splice(+t.dataset.del, 1); render(); }
  if (t.dataset.add) {                                   // chooser: add the picked type
    projects.push(PROJECT_TYPES[t.dataset.add].make(user));
    $("#chooserCard").hidden = true;
    render();
  }
  if (t.id === "addBtn") { const c = $("#chooserCard"); c.hidden = !c.hidden; }
  if (t.id === "advToggle") {
    const p = $("#advPanel"); p.hidden = !p.hidden;
    t.textContent = p.hidden ? "For your advisor · show the numbers" : "For your advisor · hide the numbers";
  }
  if (t.dataset.ai !== undefined) askAI(+t.dataset.ai);
  if (t.dataset.toggleplan !== undefined) {            // hide / show the AI advice (remembered)
    const i = +t.dataset.toggleplan, p = projects[i];
    p.planHidden = !p.planHidden; persist();
    $("#ai" + i).innerHTML = planHTML(p, i);
  }
  if (t.dataset.clearidea !== undefined) {             // empty the description box (the AI plan below stays)
    const box = t.parentElement.querySelector("textarea");
    projects[+t.dataset.clearidea].idea = ""; persist();
    box.value = ""; t.hidden = true; box.focus();
  }
});

/* ---------- init ---------- */
$("#chooser").innerHTML = Object.entries(PROJECT_TYPES)
  .map(([k, t]) => `<button type="button" data-add="${k}"><span class="ic">${t.icon}</span>${t.label}</button>`).join("");
render();
loadScore();
