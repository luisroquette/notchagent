const header = document.querySelector('[data-header]');
const reveals = document.querySelectorAll('.reveal');

const updateHeader = () => header?.classList.toggle('scrolled', window.scrollY > 20);
updateHeader();
window.addEventListener('scroll', updateHeader, { passive: true });

if ('IntersectionObserver' in window && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px' });
  reveals.forEach((element) => observer.observe(element));
} else {
  reveals.forEach((element) => element.classList.add('visible'));
}

document.querySelector('[data-copy-install]')?.addEventListener('click', async (event) => {
  const button = event.currentTarget;
  const command = document.querySelector('[data-install-command]')?.textContent?.trim();
  if (!command) return;
  try {
    await navigator.clipboard.writeText(command);
    const label = button.querySelector('span');
    if (label) label.textContent = 'Copied';
    window.setTimeout(() => { if (label) label.textContent = 'Copy commands'; }, 1800);
  } catch {
    window.getSelection()?.selectAllChildren(document.querySelector('[data-install-command]'));
  }
});

const year = document.querySelector('[data-year]');
if (year) year.textContent = String(new Date().getFullYear());

const recorder = document.querySelector('.recorder-shell');
const recorderTabs = [...document.querySelectorAll('[data-recorder-state]')];
const recorderStates = {
  steady: { quota: 58, status: 'HEALTHY', verdict: 'Current pace fits inside this window.', reset: '02:14', projected: '16%', decision: 'KEEP BUILDING', color: 'var(--amber)' },
  hot: { quota: 21, status: 'RUNNING HOT', verdict: 'At this pace, the budget ends before reset.', reset: '00:47', projected: '0%', decision: 'SLOW DOWN', color: 'var(--coral)' },
  reset: { quota: 100, status: 'RESET DETECTED', verdict: 'A fresh provider window is ready.', reset: '04:59', projected: '72%', decision: 'WINDOW OPEN', color: 'var(--green)' },
};

const setRecorderState = (stateName, focus = false) => {
  const state = recorderStates[stateName];
  if (!recorder || !state) return;
  recorder.dataset.state = stateName;
  recorder.style.setProperty('--recorder-color', state.color);
  recorder.querySelector('[data-quota-dial]')?.style.setProperty('--quota-level', `${state.quota}%`);
  recorder.querySelector('[data-quota-value]').textContent = `${state.quota}%`;
  recorder.querySelector('[data-signal-status]').textContent = state.status;
  recorder.querySelector('[data-signal-verdict]').textContent = state.verdict;
  recorder.querySelector('[data-reset-time]').textContent = state.reset;
  recorder.querySelector('[data-projected-value]').textContent = state.projected;
  recorder.querySelector('[data-decision-value]').textContent = state.decision;
  recorder.querySelector('[data-signal-rail]').style.cssText = `width:${state.quota}%;background:${state.color}`;
  recorder.querySelector('[data-signal-marker]').style.left = `${state.quota}%`;
  recorderTabs.forEach((tab) => {
    const active = tab.dataset.recorderState === stateName;
    tab.setAttribute('aria-selected', String(active));
    tab.tabIndex = active ? 0 : -1;
    if (active) {
      recorder.querySelector('#recorder-panel').setAttribute('aria-labelledby', tab.id);
      if (focus) tab.focus();
    }
  });
};

recorderTabs.forEach((tab, index) => {
  tab.addEventListener('click', () => setRecorderState(tab.dataset.recorderState));
  tab.addEventListener('keydown', (event) => {
    let next = index;
    if (event.key === 'ArrowRight') next = (index + 1) % recorderTabs.length;
    else if (event.key === 'ArrowLeft') next = (index - 1 + recorderTabs.length) % recorderTabs.length;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = recorderTabs.length - 1;
    else return;
    event.preventDefault();
    setRecorderState(recorderTabs[next].dataset.recorderState, true);
  });
});

setRecorderState('steady');
