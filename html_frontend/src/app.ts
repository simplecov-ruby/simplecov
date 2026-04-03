import hljs from 'highlight.js/lib/core';
import ruby from 'highlight.js/lib/languages/ruby';

hljs.registerLanguage('ruby', ruby);


// --- Constants ------------------------------------------------

const MAX_BAR_WIDTH = 240;
const MIN_BAR_WIDTH = 160;
const GREEN_THRESHOLD = 90;
const YELLOW_THRESHOLD = 75;

// --- Utility helpers ------------------------------------------

function $(sel: string, ctx?: Element | Document): Element | null {
  return (ctx || document).querySelector(sel);
}

function $$(sel: string, ctx?: Element | Document): Element[] {
  return Array.from((ctx || document).querySelectorAll(sel));
}

function on(
  target: EventTarget,
  event: string,
  selectorOrFn: string | ((e: Event) => void),
  fn?: (this: Element, e: Event) => void
): void {
  if (typeof selectorOrFn === 'function') {
    target.addEventListener(event, selectorOrFn);
  } else {
    target.addEventListener(event, function (e: Event) {
      const el = (e.target as Element).closest(selectorOrFn);
      if (el && (target as Element).contains(el) && fn) {
        fn.call(el, e);
      }
    });
  }
}

// --- Timeago --------------------------------------------------

function timeago(date: Date): string {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  const intervals: [number, string][] = [
    [31536000, 'year'], [2592000, 'month'], [86400, 'day'],
    [3600, 'hour'], [60, 'minute'], [1, 'second']
  ];
  for (const [secs, label] of intervals) {
    const count = Math.floor(seconds / secs);
    if (count >= 1) {
      return count === 1 ? `about 1 ${label} ago` : `${count} ${label}s ago`;
    }
  }
  return 'just now';
}

// --- Coverage helpers -----------------------------------------

function pctClass(pct: number): string {
  if (pct >= GREEN_THRESHOLD) return 'green';
  if (pct >= YELLOW_THRESHOLD) return 'yellow';
  return 'red';
}

function fmtNum(n: number): string {
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

function updateCoverageCells(
  container: Element,
  prefix: string,
  covered: number,
  total: number
): void {
  const covCell = $(prefix + '-pct', container);
  const numEl = $(prefix + '-num', container);
  const denEl = $(prefix + '-den', container);
  if (total === 0) {
    if (covCell) { covCell.innerHTML = ''; covCell.className = covCell.className.replace(/green|yellow|red/g, '').trim(); }
    if (numEl) numEl.textContent = '';
    if (denEl) denEl.textContent = '';
    return;
  }
  const p = (covered * 100.0) / total;
  const cls = pctClass(p);
  if (covCell) {
    covCell.innerHTML = `<div class="coverage-cell"><div class="bar-sizer"><div class="coverage-bar"><div class="coverage-bar__fill coverage-bar__fill--${cls}" style="width: ${p.toFixed(1)}%"></div></div></div><span class="coverage-pct">${p.toFixed(2)}%</span></div>`;
    covCell.className = `${covCell.className.replace(/green|yellow|red/g, '').trim()} ${cls}`;
  }
  if (numEl) numEl.textContent = fmtNum(covered) + '/';
  if (denEl) denEl.textContent = fmtNum(total);
}

// --- Sort state -----------------------------------------------

interface SortEntry {
  colIndex: number;
  direction: 'asc' | 'desc';
}

const sortState: Record<string, SortEntry> = {};

function getVisibleChild(row: Element, index: number): Element | null {
  let count = 0;
  for (let i = 0; i < row.children.length; i++) {
    if ((row.children[i] as HTMLElement).style.display === 'none') continue;
    if (count === index) return row.children[i];
    count++;
  }
  return null;
}

function getSortValue(td: Element | null): number | string {
  if (!td) return '';
  const order = td.getAttribute('data-order');
  if (order !== null) return parseFloat(order);
  const text = (td.textContent || '').trim();
  const num = parseFloat(text);
  return isNaN(num) ? text.toLowerCase() : num;
}

function sortTable(table: Element, colIndex: number): void {
  const tableId = table.id || table.getAttribute('data-sort-id') || 'default';
  const state = sortState[tableId] || {} as SortEntry;

  const dir: 'asc' | 'desc' =
    state.colIndex === colIndex && state.direction === 'asc' ? 'desc' : 'asc';
  sortState[tableId] = { colIndex, direction: dir };

  const tbody = table.querySelector('tbody')!;
  const rows = Array.from(tbody.querySelectorAll('tr.t-file'));

  rows.sort((a, b) => {
    const aVal = getSortValue(getVisibleChild(a, colIndex));
    const bVal = getSortValue(getVisibleChild(b, colIndex));
    let cmp: number;
    if (typeof aVal === 'number' && typeof bVal === 'number') {
      cmp = aVal - bVal;
    } else {
      cmp = String(aVal).localeCompare(String(bVal));
    }
    return dir === 'asc' ? cmp : -cmp;
  });

  tbody.append(...rows);

  // Update sort indicators
  let tdPos = 0;
  $$('thead tr:first-child th', table).forEach((th) => {
    const span = parseInt(th.getAttribute('colspan') || '1', 10);
    th.classList.remove('sorting_asc', 'sorting_desc', 'sorting');
    const isActive = colIndex >= tdPos && colIndex < tdPos + span;
    th.classList.add(isActive ? (dir === 'asc' ? 'sorting_asc' : 'sorting_desc') : 'sorting');
    tdPos += span;
  });
}

// --- Column filter types --------------------------------------

interface DataAttrPair {
  covered: string;
  total: string;
}

interface ActiveFilter {
  attrs: DataAttrPair;
  op: string;
  threshold: number;
}

const dataAttrMap: Record<string, DataAttrPair> = {
  line:   { covered: 'coveredLines',   total: 'relevantLines' },
  branch: { covered: 'coveredBranches', total: 'totalBranches' },
  method: { covered: 'coveredMethods',  total: 'totalMethods' }
};

const comparators: Record<string, (value: number, threshold: number) => boolean> = {
  gt:  (v, t) => v > t,
  gte: (v, t) => v >= t,
  eq:  (v, t) => v === t,
  lte: (v, t) => v <= t,
  lt:  (v, t) => v < t,
};

function compare(op: string, value: number, threshold: number): boolean {
  return (comparators[op] || (() => true))(value, threshold);
}

// --- Filter & totals ------------------------------------------

function parseFilters(container: Element): ActiveFilter[] {
  return $$('.col-filter__value', container)
    .map((input: Element) => {
      const inp = input as HTMLInputElement;
      if (!inp.value) return null;
      const threshold = parseFloat(inp.value);
      if (isNaN(threshold)) return null;
      const type = inp.dataset.type || '';
      const opSelect = $(`.col-filter__op[data-type="${type}"]`, container) as HTMLSelectElement | null;
      const op = opSelect ? opSelect.value : '';
      if (!op) return null;
      const attrs = dataAttrMap[type];
      if (!attrs) return null;
      return { attrs, op, threshold } as ActiveFilter;
    })
    .filter((f): f is ActiveFilter => f !== null);
}

function filterTable(container: Element): void {
  const table = $('table.file_list', container) as HTMLTableElement | null;
  if (!table) return;

  const nameInput = $('.col-filter--name', container) as HTMLInputElement | null;
  const nameQuery = nameInput ? nameInput.value : '';
  const filters = parseFilters(container);

  $$('tbody tr.t-file', table).forEach(row => {
    const htmlRow = row as HTMLElement;
    let visible = true;

    if (nameQuery) {
      const name = (row.children[0].textContent || '').toLowerCase();
      if (!name.includes(nameQuery.toLowerCase())) visible = false;
    }

    if (visible) {
      for (const f of filters) {
        const covered = parseInt(htmlRow.dataset[f.attrs.covered] || '0', 10) || 0;
        const total = parseInt(htmlRow.dataset[f.attrs.total] || '0', 10) || 0;
        const pct = total > 0 ? (covered * 100.0) / total : 100;
        if (!compare(f.op, pct, f.threshold)) { visible = false; break; }
      }
    }

    htmlRow.style.display = visible ? '' : 'none';
  });

  invalidateFileRowCache();
  updateTotalsRow(container);
  scheduleEqualizeBarWidths();
}

function updateFilterOptions(input: HTMLInputElement): void {
  const val = parseFloat(input.value);
  const wrapper = input.closest('.col-filter__coverage');
  const select = wrapper ? wrapper.querySelector('.col-filter__op') as HTMLSelectElement | null : null;
  if (!select) return;
  const gtOpt = select.querySelector('option[value="gt"]') as HTMLOptionElement | null;
  const ltOpt = select.querySelector('option[value="lt"]') as HTMLOptionElement | null;
  if (gtOpt) gtOpt.disabled = val >= 100;
  if (ltOpt) ltOpt.disabled = val <= 0;
  if (select.selectedOptions[0] && select.selectedOptions[0].disabled) {
    const first = select.querySelector('option:not(:disabled)') as HTMLOptionElement | null;
    if (first) select.value = first.value;
  }
}

function updateTotalsRow(container: Element): void {
  const rows = $$('tbody tr.t-file', container)
    .filter(r => (r as HTMLElement).style.display !== 'none');

  function sumData(attr: string): number {
    let total = 0;
    rows.forEach(r => { total += parseInt((r as HTMLElement).dataset[attr] || '0', 10) || 0; });
    return total;
  }

  const fileCount = $('.t-file-count', container);
  const totalFiles = parseInt(container.getAttribute('data-total-files') || '0', 10);
  if (fileCount) {
    const label = rows.length === 1 ? ' file' : ' files';
    fileCount.textContent = rows.length === totalFiles
      ? fmtNum(totalFiles) + label
      : fmtNum(rows.length) + '/' + fmtNum(totalFiles) + label;
  }

  for (const type of Object.keys(dataAttrMap)) {
    const attrs = dataAttrMap[type];
    const prefix = `.t-totals__${type}`;
    if (!$(prefix + '-pct', container)) continue;
    updateCoverageCells(container, prefix, sumData(attrs.covered), sumData(attrs.total));
  }
}

// --- Template materialization ----------------------------------

function materializeSourceFile(sourceFileId: string): HTMLElement | null {
  const existing = document.getElementById(sourceFileId);
  if (existing) return existing;

  const tmpl = document.getElementById('tmpl-' + sourceFileId) as HTMLTemplateElement | null;
  if (!tmpl) return null;

  const clone = document.importNode(tmpl.content, true);
  document.querySelector('.source_files')!.appendChild(clone);

  const el = document.getElementById(sourceFileId);
  if (el) {
    $$('pre code', el).forEach(e => { hljs.highlightElement(e as HTMLElement); });
  }
  return el;
}

// --- Bar width equalization ------------------------------------

function setBarSizerWidth(sizers: Element[], px: number): void {
  const w = px + 'px';
  sizers.forEach(s => {
    const st = (s as HTMLElement).style;
    st.width = w; st.minWidth = w; st.maxWidth = w;
  });
}

function equalizeBarWidths(): void {
  $$('.file_list_container').forEach(container => {
    if ((container as HTMLElement).style.display === 'none') return;
    if ((container as HTMLElement).offsetWidth === 0) return;

    const table = $('table.file_list', container) as HTMLTableElement | null;
    if (!table) return;
    const sizers = $$('.bar-sizer', table);
    if (sizers.length === 0) return;

    const wrapper = table.closest('.file_list--responsive') as HTMLElement | null;
    if (!wrapper) return;

    wrapper.style.visibility = 'hidden';

    // Binary search for the largest bar width that fits without scrolling,
    // scaling gradually from MAX_BAR_WIDTH down to MIN_BAR_WIDTH.
    // If the table overflows even at MIN_BAR_WIDTH, use MIN_BAR_WIDTH anyway.
    let lo = MIN_BAR_WIDTH, hi = MAX_BAR_WIDTH;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      setBarSizerWidth(sizers, mid);
      void table.offsetWidth;
      if (table.scrollWidth <= wrapper.clientWidth) lo = mid;
      else hi = mid - 1;
    }
    setBarSizerWidth(sizers, lo);

    wrapper.style.visibility = '';
  });
}

let equalizeRafId = 0;

function scheduleEqualizeBarWidths(): void {
  if (equalizeRafId) return;
  equalizeRafId = requestAnimationFrame(() => {
    equalizeRafId = 0;
    equalizeBarWidths();
  });
}

// --- Keyboard navigation ----------------------------------------

let focusedRow: HTMLElement | null = null;
let cachedFileRows: HTMLElement[] | null = null;

function invalidateFileRowCache(): void {
  cachedFileRows = null;
}

function getVisibleFileRows(): HTMLElement[] {
  if (cachedFileRows) return cachedFileRows;
  const visible = $$('.file_list_container').filter(c => (c as HTMLElement).style.display !== 'none');
  if (!visible.length) return [];
  cachedFileRows = $$('tbody tr.t-file', visible[0]).filter(r => (r as HTMLElement).style.display !== 'none') as HTMLElement[];
  return cachedFileRows;
}

function setFocusedRow(row: HTMLElement | null): void {
  if (focusedRow) focusedRow.classList.remove('keyboard-focus');
  focusedRow = row;
  if (focusedRow) {
    focusedRow.classList.add('keyboard-focus');
    focusedRow.scrollIntoView({ block: 'nearest' });
  }
}

function moveFocus(direction: 1 | -1): void {
  const rows = getVisibleFileRows();
  if (!rows.length) return;
  if (!focusedRow || rows.indexOf(focusedRow) === -1) {
    setFocusedRow(direction === 1 ? rows[0] : rows[rows.length - 1]);
    return;
  }
  const idx = rows.indexOf(focusedRow) + direction;
  if (idx >= 0 && idx < rows.length) setFocusedRow(rows[idx]);
}

function openFocusedRow(): void {
  if (!focusedRow) return;
  const link = focusedRow.querySelector('a.src_link');
  if (link) window.location.hash = link.getAttribute('href')!.substring(1);
}

function getMissedLines(): HTMLElement[] {
  return $$('.source-dialog .source_table li.missed, .source-dialog .source_table li.missed-branch, .source-dialog .source_table li.missed-method') as HTMLElement[];
}

function jumpToMissedLine(direction: 1 | -1): void {
  const lines = getMissedLines();
  if (!lines.length) return;

  const scrollTop = dialogBody.scrollTop;
  const midpoint = scrollTop + dialogBody.clientHeight / 2;

  if (direction === 1) {
    const next = lines.find(li => li.offsetTop > midpoint);
    const target = next || lines[0];
    dialogBody.scrollTop = target.offsetTop - dialogBody.clientHeight / 3;
  } else {
    let prev: HTMLElement | null = null;
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].offsetTop < midpoint - 10) { prev = lines[i]; break; }
    }
    const target = prev || lines[lines.length - 1];
    dialogBody.scrollTop = target.offsetTop - dialogBody.clientHeight / 3;
  }
}

// --- Source file dialog ----------------------------------------

let dialog: HTMLDialogElement;
let dialogBody: HTMLElement;
let dialogTitle: HTMLElement;
let activeSourceEl: HTMLElement | null = null;
let savedHeaderHTML = '';

function restoreActiveSource(): void {
  if (!activeSourceEl) return;
  if (savedHeaderHTML) {
    activeSourceEl.insertAdjacentHTML('afterbegin', savedHeaderHTML);
    savedHeaderHTML = '';
  }
  const container = document.querySelector('.source_files');
  if (container) container.appendChild(activeSourceEl);
  activeSourceEl = null;
}

function openSourceFile(sourceFileId: string, linenumber?: string): void {
  restoreActiveSource();

  const el = materializeSourceFile(sourceFileId);
  if (!el) return;

  const header = el.querySelector('.header');
  if (header) {
    savedHeaderHTML = header.outerHTML;
    dialogTitle.innerHTML = header.innerHTML;
    header.remove();
  }

  activeSourceEl = el;
  dialogBody.appendChild(el);

  if (!dialog.open) dialog.showModal();
  document.documentElement.style.overflow = 'hidden';
  dialogBody.focus();

  if (linenumber) {
    const targetLine = dialogBody.querySelector('li[data-linenumber="' + linenumber + '"]') as HTMLElement | null;
    if (targetLine) dialogBody.scrollTop = targetLine.offsetTop;
  }
}

function showFileList(tabId: string): void {
  setFocusedRow(null);
  invalidateFileRowCache();

  if (dialog.open) {
    restoreActiveSource();
    dialog.close();
    dialogBody.innerHTML = '';
    dialogTitle.innerHTML = '';
    document.documentElement.style.overflow = '';
  }

  if (tabId) {
    const tab = document.querySelector('.group_tabs a.' + tabId);
    if (tab) {
      $$('.group_tabs li').forEach(li => li.classList.remove('active'));
      tab.parentElement!.classList.add('active');
      $$('.file_list_container').forEach(c => (c as HTMLElement).style.display = 'none');
      const target = document.getElementById(tabId);
      if (target) target.style.display = '';
    }
  }
  const wrapper = document.getElementById('wrapper');
  if (wrapper && !wrapper.classList.contains('hide')) {
    scheduleEqualizeBarWidths();
  }
}

function navigateToHash(): void {
  const hash = window.location.hash.substring(1);

  if (!hash) {
    const firstTab = document.querySelector('.group_tabs a');
    if (firstTab) showFileList(firstTab.getAttribute('href')!.replace('#', ''));
    return;
  }

  if (hash.charAt(0) === '_') {
    showFileList(hash.substring(1));
  } else {
    const parts = hash.split('-L');
    if (!document.querySelector('.group_tabs li.active')) {
      const first = document.querySelector('.group_tabs li');
      if (first) first.classList.add('active');
    }
    openSourceFile(parts[0], parts[1]);
  }
}

function navigateToActiveTab(): void {
  const activeLink = document.querySelector('.group_tabs li.active a');
  if (activeLink) {
    window.location.hash = activeLink.getAttribute('href')!.replace('#', '#_');
  }
}

// --- Dark mode ------------------------------------------------

function initDarkMode(): void {
  const toggle = document.getElementById('dark-mode-toggle');
  if (!toggle) return;

  const root = document.documentElement;

  function isDark(): boolean {
    return root.classList.contains('dark-mode') ||
      (!root.classList.contains('light-mode') &&
        window.matchMedia('(prefers-color-scheme: dark)').matches);
  }

  function updateLabel(): void {
    toggle!.textContent = isDark() ? '\u2600\uFE0F Light' : '\uD83C\uDF19 Dark';
  }

  updateLabel();

  toggle.addEventListener('click', () => {
    const switchToLight = isDark();
    root.classList.toggle('light-mode', switchToLight);
    root.classList.toggle('dark-mode', !switchToLight);
    localStorage.setItem('simplecov-dark-mode', switchToLight ? 'light' : 'dark');
    updateLabel();
  });

  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if (!localStorage.getItem('simplecov-dark-mode')) updateLabel();
  });
}

// --- Initialization -------------------------------------------

document.addEventListener('DOMContentLoaded', function () {
  // Timeago
  $$('abbr.timeago').forEach(el => {
    const date = new Date(el.getAttribute('title') || '');
    if (!isNaN(date.getTime())) el.textContent = timeago(date);
  });

  initDarkMode();

  // Table sorting — compute td index dynamically at click time
  function thToTdIndex(table: Element, clickedTh: Element): number {
    let idx = 0;
    for (const th of $$('thead tr:first-child th', table)) {
      const span = parseInt(th.getAttribute('colspan') || '1', 10);
      if (th === clickedTh) return idx + span - 1;
      idx += span;
    }
    return idx;
  }

  $$('table.file_list').forEach(table => {
    $$('thead tr:first-child th', table).forEach((th) => {
      th.classList.add('sorting');
      (th as HTMLElement).style.cursor = 'pointer';
      th.addEventListener('click', () => sortTable(table, thToTdIndex(table, th)));
    });
  });

  // Filter options init
  $$('.col-filter__value').forEach(el => updateFilterOptions(el as HTMLInputElement));

  // Prevent filter clicks from triggering sort
  $$('.col-filter--name, .col-filter__op, .col-filter__value, .col-filter__coverage').forEach(el => {
    el.addEventListener('click', e => e.stopPropagation());
  });

  // Filter change handlers
  on(document, 'input', '.col-filter--name, .col-filter__op, .col-filter__value', function () {
    if (this.classList.contains('col-filter__value')) updateFilterOptions(this as HTMLInputElement);
    filterTable(this.closest('.file_list_container')!);
  });
  on(document, 'change', '.col-filter__op, .col-filter__value', function () {
    if (this.classList.contains('col-filter__value')) updateFilterOptions(this as HTMLInputElement);
    filterTable(this.closest('.file_list_container')!);
  });

  // Keyboard shortcuts
  document.addEventListener('keydown', (e: KeyboardEvent) => {
    const inInput = (e.target as Element).matches('input, select, textarea');

    // "/" to focus search
    if (e.key === '/' && !inInput) {
      e.preventDefault();
      const visible = $$('.file_list_container').filter(c => (c as HTMLElement).style.display !== 'none');
      const input = visible.length ? $('.col-filter--name', visible[0]) as HTMLElement | null : null;
      if (input) input.focus();
      return;
    }

    // Escape — close dialog or clear focus
    if (e.key === 'Escape') {
      if (dialog.open) {
        e.preventDefault();
        navigateToActiveTab();
      } else if (inInput) {
        (e.target as HTMLElement).blur();
      } else if (focusedRow) {
        setFocusedRow(null);
      }
      return;
    }

    if (inInput) return;

    // Source view shortcuts (dialog open)
    if (dialog.open) {
      if (e.key === 'n' && !e.shiftKey) { e.preventDefault(); jumpToMissedLine(1); }
      if (e.key === 'N' || (e.key === 'n' && e.shiftKey) || e.key === 'p') { e.preventDefault(); jumpToMissedLine(-1); }
      return;
    }

    // File list shortcuts (dialog closed)
    if (e.key === 'j') { e.preventDefault(); moveFocus(1); }
    if (e.key === 'k') { e.preventDefault(); moveFocus(-1); }
    if (e.key === 'Enter' && focusedRow) { e.preventDefault(); openFocusedRow(); }
  });

  // Dialog setup
  dialog = document.getElementById('source-dialog') as HTMLDialogElement;
  dialogBody = document.getElementById('source-dialog-body')!;
  dialogTitle = document.getElementById('source-dialog-title')!;

  dialog.querySelector('.source-dialog__close')!.addEventListener('click', navigateToActiveTab);
  dialog.addEventListener('click', e => { if (e.target === dialog) navigateToActiveTab(); });

  // Event delegation for dynamic content
  on(document, 'click', '.t-missed-method-toggle', function (e: Event) {
    e.preventDefault();
    const parent = this.closest('.header') || this.closest('.source-dialog__title') || this.closest('.source-dialog__header');
    const list = parent ? parent.querySelector('.t-missed-method-list') as HTMLElement | null : null;
    if (list) list.style.display = list.style.display === 'none' ? '' : 'none';
  });

  on(document, 'click', 'a.src_link', function (e: Event) {
    e.preventDefault();
    window.location.hash = this.getAttribute('href')!.substring(1);
  });

  on(document, 'click', 'table.file_list tbody tr', function (e: Event) {
    if ((e.target as Element).closest('a')) return;
    const link = this.querySelector('a.src_link');
    if (link) window.location.hash = link.getAttribute('href')!.substring(1);
  });

  on(document, 'click', '.source-dialog .source_table li[data-linenumber]', function (e: Event) {
    e.preventDefault();
    dialogBody.scrollTop = (this as HTMLElement).offsetTop;
    const linenumber = (this as HTMLElement).dataset.linenumber;
    const sourceFileId = window.location.hash.substring(1).replace(/-L.*/, '');
    window.location.replace(window.location.href.replace(/#.*/, '#' + sourceFileId + '-L' + linenumber));
  });

  window.addEventListener('hashchange', navigateToHash);

  // Tab system
  document.querySelector('.source_files')!.setAttribute('style', 'display:none');
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

  // Equalize bar column widths within each table
  window.addEventListener('resize', scheduleEqualizeBarWidths);

  // Initial state
  navigateToHash();

  // Finalize loading
  clearInterval((window as any)._simplecovLoadingTimer);
  clearTimeout((window as any)._simplecovShowTimeout);

  const loadingEl = document.getElementById('loading');
  if (loadingEl) {
    loadingEl.style.transition = 'opacity 0.3s';
    loadingEl.style.opacity = '0';
    setTimeout(() => { loadingEl.style.display = 'none'; }, 300);
  }

  const wrapperEl = document.getElementById('wrapper');
  if (wrapperEl) wrapperEl.classList.remove('hide');

  // Equalize bar widths now that wrapper is visible
  equalizeBarWidths();

});
