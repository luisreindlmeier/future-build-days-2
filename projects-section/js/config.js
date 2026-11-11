/* =====================================================================
   CONFIG — every rule, rate, market figure and persona lives here.
   Edit this file before the pitch; nothing else needs touching.
   ===================================================================== */

const CFG = {
  startYM: 2026 * 12 + 10, // Nov 2026

  rates: {
    carLoan: 0.065, carMonths: 48, carFinanceShare: 0.80, carRunning: 250,
    mortgage: 0.0425, mortgageRepay: 0.02, purchaseCosts: 0.12,
    incomeGrowth: 0.03,
    studiesLoan: 0.065,                  // KfW-style student loan
    bizLoan: 0.07                        // business start-up loan (KfW-style); used to re-check the AI's loan payment
  },

  caps: {
    carPct: 0.15, carPctAdjust: 0.25,     // car: total mobility cost vs income
    homePct: 0.35, homePctAdjust: 0.45,   // home: mortgage vs income
    tripGoodX: 1, tripAdjustX: 2,         // trip: cost vs monthly income
    bizRunwayMonths: 6,                   // business: personal runway needed
    foundationGate: 40,                   // below this vital: no financing at all
    cushionShare: 0.30                    // share of saving that fills the cushion
  },

  cities: [
    ["Munich", 9070], ["Hamburg", 6394], ["Frankfurt", 6293], ["Berlin", 5796],
    ["Düsseldorf", 5164], ["Cologne", 5029], ["Stuttgart", 4737],
    ["Leipzig", 3121], ["Germany average", 2712]
  ],

  market: { evAvg: 39658, evSrc: "AutoScout24, Oct 2026" },

  // ===================== AI CONNECTION =====================
  // key: the ONLY place the AI key is set (the customer never sees it).
  //      (Do NOT publish this repo with a real key inside.)
  // The provider is detected from the key: sk-ant… = Anthropic (Claude),
  // AIza… or AQ.… = Google (Gemini, free key at aistudio.google.com),
  // gsk_… = Groq (free key at console.groq.com), sk-bf-… = hessian.AI gateway,
  // sk-proj-… / sk-… = OpenAI (paid, platform.openai.com).
  // Your sk-bf-… key is the hIP key from the JAIF handbook (JUPITER AI
  // Factory, Futury Build Days #4). It speaks the OpenAI protocol at the
  // gateway below; GLM-5.3-Flash is the handbook's tool-capable pick.
  // The gateway allows direct browser calls from http:// pages, so no proxy
  // is needed. Open index.html with VS Code Live Server, not by double-click
  // (file:// pages get blocked with CORS 403).
  ai: {
    key: typeof AI_KEY !== "undefined" ? AI_KEY : "",   // set in js/secrets.js (not in git) — see js/secrets.example.js
    anthropic: { endpoint: "https://api.anthropic.com/v1/messages", model: "claude-sonnet-5-5", version: "2023-06-01" },
    chatgpt:   { endpoint: "https://api.openai.com/v1/chat/completions", model: "gpt-5-mini" },  // change the model here if your account has another
    openai:    { endpoint: "https://hip-gw.hessian.ai/v1/chat/completions", model: "zai-glm-flash/GLM-5.3-Flash" },  // hessian.AI gateway (sk-bf-… keys)
    gemini:    { endpoint: "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent", model: "gemini-3.5-flash",
                 // tested Nov 2026: 3.5-flash ~4 s and correct math; 3.7/3.8-flash hung > 60 s;
                 // flash-lite is ~3 s but got the mortgage math wrong → only a fallback.
                 fallbacks: ["gemini-3.5-flash-lite", "gemini-flash-latest", "gemini-3.5-flash-lite"], timeoutMs: 30000 },
                 // order matters: lite answers in ~3 s; flash-latest often hangs, so it comes after;
                 // lite is listed twice = one more try if its reply was broken.
                 // Free tier = only ~20 requests/day per model; a model out of quota is skipped.
    groq:      { endpoint: "https://api.groq.com/openai/v1/chat/completions", model: "openai/gpt-oss-120b" }  // see console.groq.com/docs/models
  }
};

/* ===================== THE SCORE (constant for now) =====================
   This is the scan result the AI thinks from. For now it is a constant;
   when the scan backend is ready, set SCORE_API_URL and the app will
   fetch this same shape from there instead (see loadScore in app.js). */
const SCORE_API_URL = ""; // e.g. "https://your-api.example.com/score/123" — leave "" to use the constant

const SCAN = {
  name: "Lena",
  income: 2600,        // net income per month, EUR
  costs: 1800,         // living costs per month, EUR
  capacity: 900,       // how much she can put aside per month, EUR
  savings: 6000,       // total savings today, EUR
  vitals: { Foundation: 62, Habits: 48, Knowledge: 55, Future: 40, Calm: 70 }, // 0–100
  level: "Rooted"      // Seed / Sprout / Rooted / Thriving / Flourishing
};

/* Catalog for the "+ Add a project" chooser.
   make(user) returns a fresh project with sensible defaults. */
const PROJECT_TYPES = {
  car: {
    label: "Buy a car", icon: "🚗",
    ask: "e.g. A used VW ID.3 for commuting 40 km a day in Frankfurt, I can charge at work.",
    db: "Online-PrivatKredit (3.25–11.74% eff.) — total interest shown before you sign.",
    make: () => ({ type: "car", name: "Buy a car", budget: 15000, finance: true, targetM: 12 })
  },
  home: {
    label: "Buy a home", icon: "⌂",
    ask: "e.g. A 3-room flat for my partner and me in Munich, near the S-Bahn, needs a new kitchen.",
    db: "ROBIN / maxblue to grow equity now · Baufinanzierung when the 35% light turns green.",
    make: () => ({ type: "home", name: "Buy a home", city: 0, sqm: 50, targetM: 96 })
  },
  trip: {
    label: "A big trip", icon: "✈", noLoan: true,
    ask: "e.g. Three weeks in Japan for two people in April: Tokyo, Kyoto, Osaka, mid-range hotels.",
    db: "Mastercard Travel — €94 a year, no foreign-currency fee.",
    make: () => ({ type: "trip", name: "A big trip", cost: 2500, targetM: 10 })
  },
  business: {
    label: "Start a business", icon: "🚀",
    ask: "e.g. A small pizza restaurant in Cologne, about 40 seats, 3 employees, open 6 days a week, also delivery.",
    db: "Gründerkonto (€0 in year one) · KfW StartGeld up to €125,000 — with an advisor.",
    make: () => ({ type: "business", name: "Start a business", cost: 35000, targetM: 24, idea: "" })
  },
  family: {
    label: "Start a family", icon: "👶", noLoan: true,
    ask: "e.g. First baby next year, we live in Berlin, I take 12 months parental leave, daycare after that.",
    db: "Zurich partnership: disability and life cover — the protections this moment needs.",
    make: () => ({ type: "family", name: "Start a family", cost: 10000, targetM: 36 })
  },
  studies: {
    label: "Studies abroad", icon: "🎓",
    ask: "e.g. A 2-year master in computer science in Amsterdam, starting September 2027.",
    db: "Savings plan first; student financing only with an advisor.",
    make: () => ({ type: "studies", name: "Studies abroad", cost: 25000, targetM: 30 })
  },
  sabbatical: {
    label: "A sabbatical", icon: "🌴", noLoan: true,
    ask: "e.g. Six months off to travel South America and volunteer, keeping my flat in Hamburg.",
    db: "A separate pot sized at 6 months of your real costs.",
    make: (user) => ({ type: "sabbatical", name: "A sabbatical", cost: 6 * user.costs, targetM: 36 })
  }
};

/* Projects a NEW user starts with: none — they add their own with "+ Add a project".
   Everything they add (sliders, descriptions, AI plans) is saved in the browser
   (localStorage "kairos-projects") and comes back on the next visit.
   For a demo you can put examples back here, e.g.
   { type: "trip", name: "Japan, three weeks", cost: 2500, targetM: 10 } */
const DEFAULT_PROJECTS = [];
