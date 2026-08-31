
import { $$, on } from './dom';
import { timeago, timeagoNextTick, precomputeFileIds } from './format';
import { renderPage } from './page';
import { setupTableSorting } from './sort';
import { setupColumnFilters } from './filter';
import { scheduleEqualizeBarWidths, equalizeBarWidths } from './bar_width';
import { setupSourceDialog, navigateToHash } from './dialog';
import { setupEventDelegation } from './events';
import { initDarkMode, initColorblindMode, handleKeydown } from './controls';
import { setupTabScrollFade } from './tab_scroll';

function scheduleTimeago(): void {
  let minDelay = Infinity;
  $$('abbr.timeago').forEach(el => {
    const date = new Date(el.getAttribute('title') || '');
    if (Number.isNaN(date.getTime())) return;
    el.textContent = timeago(date);
    minDelay = Math.min(minDelay, timeagoNextTick(date));
  });
  if (minDelay < Infinity) setTimeout(scheduleTimeago, minDelay);
}

function setupTabs(): void {
  $$('.file_list_container').forEach(c => (c as HTMLElement).style.display = 'none');

  $$('.file_list_container').forEach(container => {
    const id = container.id;
    const groupName = container.querySelector('.group_name');
    const coveredPct = container.querySelector('.covered_percent');

    const li = document.createElement('li');
    li.setAttribute('role', 'tab');
    const a = document.createElement('a');
    a.href = '#' + id;
    a.className = id;
    a.innerHTML = (groupName ? groupName.innerHTML : '') + ' (' + (coveredPct ? coveredPct.innerHTML : '') + ')';
    li.appendChild(a);
    document.querySelector('.group_tabs')!.appendChild(li);
  });

  on(document.querySelector('.group_tabs')!, 'click', 'a', function (e: Event) {
    e.preventDefault();
    window.location.hash = this.getAttribute('href')!.replace('#', '#_');
  });
}

function finishLoading(loadingEl: HTMLElement | null): void {
  if (loadingEl) {
    loadingEl.style.transition = 'opacity 0.3s';
    loadingEl.style.opacity = '0';
    setTimeout(() => { loadingEl.style.display = 'none'; }, 300);
  }

  const wrapperEl = document.getElementById('wrapper');
  if (wrapperEl) wrapperEl.classList.remove('hide');

  equalizeBarWidths();
}

async function init(): Promise<void> {
  const data = window.SIMPLECOV_DATA;

  const loadingEl = document.getElementById('loading');
  if (loadingEl) loadingEl.style.display = '';

  await precomputeFileIds(Object.keys(data.coverage));

  renderPage(data);

  scheduleTimeago();
  initDarkMode();
  initColorblindMode();
  setupTableSorting(data.meta.primary_coverage);
  setupColumnFilters();
  document.addEventListener('keydown', handleKeydown);
  setupSourceDialog();
  setupEventDelegation();
  setupTabs();
  setupTabScrollFade();

  window.addEventListener('resize', scheduleEqualizeBarWidths);

  navigateToHash();

  finishLoading(loadingEl);
}

document.addEventListener('DOMContentLoaded', init);
