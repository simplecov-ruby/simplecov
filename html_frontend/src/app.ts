// Entry point: wires the rendered page to its interactions on DOMContentLoaded.
// esbuild bundles this module and everything it imports into application.js.

import { $$, on } from './dom';
import { timeago, timeagoNextTick, precomputeFileIds } from './format';
import { renderPage } from './page';
import { setupTableSorting } from './sort';
import { setupColumnFilters } from './filter';
import { scheduleEqualizeBarWidths, equalizeBarWidths } from './bar_width';
import { setupSourceDialog, navigateToHash } from './dialog';
import { setupEventDelegation } from './events';
import { initDarkMode, handleKeydown } from './controls';

// Timeago — schedule the next update for exactly when the text would change.
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

// Build the group tab bar from the rendered file-list containers.
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

// Render the coverage page. Both `application.js` and `coverage_data.js`
// use `defer`, so `coverage_data.js` is guaranteed to have populated
// `window.SIMPLECOV_DATA` by the time `DOMContentLoaded` fires.
async function init(): Promise<void> {
  const data = window.SIMPLECOV_DATA;

  // Show loading indicator
  const loadingEl = document.getElementById('loading');
  if (loadingEl) loadingEl.style.display = '';

  // Web Crypto's digest API is async, so resolve every file's id up front;
  // every renderer downstream looks them up synchronously.
  await precomputeFileIds(Object.keys(data.coverage));

  // Render all content from data
  renderPage(data);

  scheduleTimeago();
  initDarkMode();
  setupTableSorting();
  setupColumnFilters();
  document.addEventListener('keydown', handleKeydown);
  setupSourceDialog();
  setupEventDelegation();
  setupTabs();

  // Equalize bar column widths
  window.addEventListener('resize', scheduleEqualizeBarWidths);

  // Initial state
  navigateToHash();

  // Finalize loading
  finishLoading(loadingEl);
}

document.addEventListener('DOMContentLoaded', init);
