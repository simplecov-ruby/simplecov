
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

export function scheduleTimeago(): void {
  let minDelay = Infinity;
  $$('abbr.timeago').forEach(el => {
    const title = el.getAttribute('title');
    if (!title) return;
    const date = new Date(title);
    if (Number.isNaN(date.getTime())) return;
    el.textContent = timeago(date);
    minDelay = Math.min(minDelay, timeagoNextTick(date));
  });
  if (minDelay < Infinity) setTimeout(scheduleTimeago, minDelay);
}

function setupTabs(): void {
  $$('.file_list_container').forEach(c => (c as HTMLElement).style.display = 'none');

  $$('.file_list_container').forEach(container => {
    const li = document.createElement('li');
    li.setAttribute('role', 'tab');
    const a = document.createElement('a');
    a.href = '#' + container.id;
    a.className = container.id;
    a.innerHTML = `${container.querySelector('.group_name')!.innerHTML} (${container.querySelector('.covered_percent')!.innerHTML})`;
    li.appendChild(a);
    document.querySelector('.group_tabs')!.appendChild(li);
  });

  on(document.querySelector('.group_tabs')!, 'click', 'a', function (e: Event) {
    e.preventDefault();
    window.location.hash = this.getAttribute('href')!.replace('#', '#_');
  });
}

function finishLoading(loadingEl: HTMLElement): void {
  loadingEl.style.transition = 'opacity 0.3s';
  loadingEl.style.opacity = '0';
  setTimeout(() => { loadingEl.style.display = 'none'; }, 300);

  document.getElementById('wrapper')!.classList.remove('hide');

  equalizeBarWidths();
}

async function init(): Promise<void> {
  const data = window.SIMPLECOV_DATA;

  const loadingEl = document.getElementById('loading')!;
  loadingEl.style.display = '';

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
