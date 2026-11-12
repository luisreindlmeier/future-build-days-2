'use strict';
/* Motion and small touches for the glass theme. dashboard.js calls uiEnhance() after every render.
   Entrance animations and count-ups run only when the page or customer changes, not on the
   prediction loader's repeated renders. Respects prefers-reduced-motion. */
const UI = {last: '', calm: matchMedia('(prefers-reduced-motion: reduce)').matches};

function uiEnhance() {
  const main = document.getElementById('main');
  if (!main) return;
  const key = (typeof customer !== 'undefined' ? customer : '') + location.hash + (main.querySelector('.pred-loader') ? ':loading' : '');
  const fresh = key !== UI.last;
  UI.last = key;
  uiAvatar();
  if (!fresh || UI.calm) return;
  // stagger the page's blocks and cards
  main.classList.remove('enter');
  void main.offsetWidth;                                   // restart the animation
  let i = 0;
  main.querySelectorAll(':scope>*, .grid>.card, .action-list>.card').forEach(el => el.style.setProperty('--i', Math.min(i++, 12)));
  main.classList.add('enter');
  // count up the big numbers
  main.querySelectorAll('.metric strong, .score-ring b, .pred-big .from, .pred-big .to, .t3-big, .lp-ring b').forEach(countUp);
}

function countUp(el) {
  const node = [...el.childNodes].find(n => n.nodeType === 3 && /\d/.test(n.textContent));
  if (!node) return;
  const m = /^(\D*)([\d.,]+)(.*)$/s.exec(node.textContent);
  if (!m) return;
  const raw = m[2].replace(/,/g, ''), target = parseFloat(raw), dec = (raw.split('.')[1] || '').length;
  if (!isFinite(target) || target === 0) return;
  const t0 = performance.now(), dur = 1100;
  const fmt = v => v.toLocaleString('en', {minimumFractionDigits: dec, maximumFractionDigits: dec});
  const step = now => {
    if (!node.isConnected) return;
    const p = Math.min(1, (now - t0) / dur), e = 1 - Math.pow(1 - p, 3);
    node.textContent = m[1] + fmt(target * e) + m[3];
    if (p < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

function uiAvatar() {
  const label = document.querySelector('.persona');
  if (!label) return;
  let a = label.querySelector('.avatar');
  if (!a) { a = document.createElement('span'); a.className = 'avatar'; a.setAttribute('aria-hidden', 'true'); label.prepend(a); }
  const name = (typeof workspace !== 'undefined' && workspace?.tree?.name) || '';
  a.textContent = name ? name[0].toUpperCase() : '·';
}

// a soft light that follows the pointer over glass cards
document.addEventListener('pointermove', e => {
  const card = e.target.closest && e.target.closest('.card');
  if (!card) return;
  const r = card.getBoundingClientRect();
  card.style.setProperty('--mx', (e.clientX - r.left) + 'px');
  card.style.setProperty('--my', (e.clientY - r.top) + 'px');
}, {passive: true});
