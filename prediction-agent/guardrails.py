#!/usr/bin/env python3
"""
GUARDRAILS  -  shared output checks for the Prediction and Action agents.

Every text the LLM writes is checked before anyone sees it:
  - numbers:  every EUR amount, %, point difference, duration and plain number must appear in the
              facts the agent was given for that field (EUR compared by value: €1.07m == €1,070k)
  - scenario: a field about scenario X may only use numbers from X, the baseline and the customer
  - words:    no promises, no marketing or emotional language, no "eliminated/removed/gone" unless the
              facts show 0% for that risk AND the sentence says "in the simulation"
  - ids:      no raw ids such as save_more_tomorrow in customer-facing text
Violations are logged to the console and to guardrail.log (JSON lines) so the guardrail can be shown.
"""
import datetime
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LOG_FILE = os.path.join(HERE, "guardrail.log")
NOISE_POINTS = 2      # differences below this many percentage points are Monte Carlo noise (2,000 paths)

_EUR = re.compile(r"[−-]?€\s?(\d[\d,]*(?:\.\d+)?)\s?([km])?(?![a-z])", re.I)
_PCT = re.compile(r"(\d+(?:\.\d+)?)\s?%")
_PTS = re.compile(r"(\d+)\s(?:percentage\s)?points?\b", re.I)
_DUR = re.compile(r"(\d+(?:[.,]\d+)?)\s(years?|months?)\b", re.I)
_NUM = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])")

FORBIDDEN = re.compile(
    r"\b(guarantee\w*|safe|safely|safety net|certain|certainly|certainty|peace of mind|legacy|real freedom|"
    r"start today|risk[- ]free|worry[- ]free|life's work|dream\w*|will definitely|expected return|we recommend|"
    r"you should (buy|sell|invest in)|\d+ (out )?of (10|ten))\b", re.I)
REMOVAL = re.compile(r"\b(eliminat\w*|remov\w*|gone|wipes? out|no longer (a )?risk)\b", re.I)
SECURITIES = re.compile(
    r"\b(sell|selling|sold|buy|buying)\b[^.;]{0,40}\b(shares?|stocks?|funds?|etfs?|bonds?|crypto\w*|bitcoin|securities|equities)\b"
    r"|\b(shares?|stocks?|funds?|etfs?|bonds?|crypto\w*|securities)\b[^.;]{0,25}\b(sell|selling|buy|buying)\b", re.I)
RAW_ID = re.compile(r"\b[a-z]+(?:_[a-z0-9]+)+\b")


def eur_value(num, suffix):
    v = float(num.replace(",", ""))
    return v * {"k": 1e3, "m": 1e6}.get((suffix or "").lower(), 1)


def numbers(text):
    """All number tokens in a text: ('eur', value) ('pct', v) ('pts', v) ('dur', v, unit) ('num', v)."""
    out, spans = [], []

    def take(rx, kind):
        for m in rx.finditer(text):
            if any(a <= m.start() < b for a, b in spans):
                continue
            spans.append((m.start(), m.end()))
            if kind == "eur":
                out.append(("eur", eur_value(m.group(1), m.group(2)), m.group(0).strip()))
            elif kind == "dur":
                out.append(("dur", float(m.group(1).replace(",", ".")), m.group(2).lower().rstrip("s"), m.group(0)))
            else:
                out.append((kind, float(m.group(1)), m.group(0)))
    take(_EUR, "eur")
    take(_DUR, "dur")
    take(_PTS, "pts")
    take(_PCT, "pct")
    take(_NUM, "num")
    return out


class Facts:
    """The set of numbers a field may use, built from any JSON-able facts."""

    def __init__(self, *objs):
        self.eur, self.pct, self.pts, self.dur, self.num = [], set(), {0.0}, {(12.0, "month"), (1.0, "year")}, set()
        for o in objs:
            self.add(o)

    def add(self, obj):
        text = obj if isinstance(obj, str) else json.dumps(obj, ensure_ascii=False)
        for t in numbers(text):
            k, v = t[0], t[1]
            if k == "eur":
                self.eur.append(v)
            elif k == "pct":
                self.pct.add(v)
            elif k == "pts":
                self.pts.add(v)
            elif k == "dur":
                self.dur.add((v, t[2]))
            self.num.add(v)
        for m in re.finditer(r"[+−-](\d+) points?", text):     # "+5 points" in the facts
            self.pts.add(float(m.group(1)))
        return self

    def __or__(self, other):
        f = Facts()
        for a in ("eur",):
            setattr(f, a, getattr(self, a) + getattr(other, a))
        for a in ("pct", "pts", "dur", "num"):
            setattr(f, a, getattr(self, a) | getattr(other, a))
        return f

    def has(self, tok):
        k, v = tok[0], tok[1]
        if k == "eur":
            return any(abs(v - a) <= max(1.0, 0.006 * max(v, a)) for a in self.eur)
        if k == "pct":
            return v in self.pct
        if k == "pts":
            return v in self.pts
        if k == "dur":
            return (v, tok[2]) in self.dur
        return v in self.num or v in self.pct or v in self.pts or any(v == d[0] for d in self.dur) or v <= 3


def check_text(text, facts, removed_ok=False, ids=()):
    """Violations for one customer-facing text. removed_ok: this field's scenario has a risk at 0%."""
    v = []
    if not isinstance(text, str):
        return v
    bad = [t[-1] for t in numbers(text) if not facts.has(t)]
    if bad:
        v.append("numbers not in the facts for this part: " + ", ".join(sorted(set(bad))))
    m = FORBIDDEN.search(text)
    if m:
        v.append(f"forbidden wording: '{m.group(0)}'")
    if SECURITIES.search(text):
        v.append("buy/sell instruction about securities")
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        r = REMOVAL.search(sentence)
        if r and not (removed_ok and "in the simulation" in sentence.lower()):
            v.append(f"'{r.group(0)}' is only allowed for a risk at 0%, with 'in the simulation'")
    raw = [x for x in RAW_ID.findall(text) if not ids or x in ids]
    if raw:
        v.append("raw id in text: " + ", ".join(sorted(set(raw))))
    return v


def qualify_removals(text, removed_ok):
    """If a sentence says a risk is removed and the facts show 0% for it, add the required qualifier
    "in the simulation" instead of rejecting a true sentence. Returns (text, changed)."""
    if not isinstance(text, str) or not removed_ok:
        return text, False
    out, changed = [], False
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        if REMOVAL.search(sentence) and "in the simulation" not in sentence.lower():
            body = sentence.rstrip()
            end = body[-1] if body and body[-1] in ".!?" else ""
            sentence = (body[:-1] if end else body) + " in the simulation" + (end or ".")
            changed = True
        out.append(sentence)
    return " ".join(out), changed


def log(agent, model, attempt, violations, replaced=None):
    """Write guardrail events to the console and guardrail.log."""
    if not violations and not replaced:
        return
    rec = {"time": datetime.datetime.now().isoformat(timespec="seconds"), "agent": agent, "model": model,
           "attempt": attempt, "violations": violations, "replaced_fields": replaced or {}}
    try:
        with open(LOG_FILE, "a", encoding="utf8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError:
        pass
    n = sum(len(x) for x in violations.values()) if isinstance(violations, dict) else len(violations)
    what = "replaced by rules: " + ", ".join(replaced) if replaced else "asking the model to fix them"
    sys.stderr.write(f"[guardrail] {agent} attempt {attempt}: {n} violation(s), {what}\n")
    items = violations.items() if isinstance(violations, dict) else [("", violations)]
    for field, msgs in items:
        for msg in msgs:
            sys.stderr.write(f"[guardrail]   {field}: {msg}\n")
