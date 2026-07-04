// Column sorting for the file-list tables, including click-to-sort wiring and
// the per-table sort-direction state.

import { $$ } from './dom';
import { applyRowWindow } from './row_window';

interface SortEntry {
  colIndex: number;
  direction: 'asc' | 'desc';
}

const sortState: Record<string, SortEntry> = {};

// Actual child index of the `index`-th visible cell in a row. The coverage
// filter hides whole columns, so this mapping is uniform across rows and is
// computed once per sort from the first row, rather than allocating a filtered
// array for every row.
function visibleChildIndex(row: Element, index: number): number | null {
  let visible = 0;
  const children = row.children;
  for (let i = 0; i < children.length; i++) {
    if ((children[i] as HTMLElement).style.display === 'none') continue;
    if (visible === index) return i;
    visible += 1;
  }
  return null;
}

function getSortValue(td: Element | null): number | string {
  if (!td) return '';
  const order = td.getAttribute('data-order');
  if (order !== null) return Number.parseFloat(order);
  const text = (td.textContent || '').trim();
  const num = Number.parseFloat(text);
  return Number.isNaN(num) ? text.toLowerCase() : num;
}

// Cell contents never change after render (filters only toggle row
// visibility), so sort values are cached per row for the life of the page.
// Keyed by the row's actual child index, which is stable however the sort
// column was resolved.
const rowValueCache = new WeakMap<Element, Map<number, number | string>>();

function cachedSortValue(row: Element, childIndex: number | null): number | string {
  if (childIndex === null) return '';
  let cache = rowValueCache.get(row);
  if (!cache) {
    cache = new Map();
    rowValueCache.set(row, cache);
  }
  const hit = cache.get(childIndex);
  if (hit !== undefined) return hit;
  const value = getSortValue(row.children[childIndex] ?? null);
  cache.set(childIndex, value);
  return value;
}

// A cached collator compares markedly faster than calling `String.localeCompare`
// per comparison, which matters when sorting thousands of rows by file name.
// Left with default options so the ordering matches the previous behavior.
const collator = new Intl.Collator();

// Compare two cell values numerically when both are numbers, otherwise
// as case-insensitive strings.
function compareValues(a: number | string, b: number | string): number {
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  return collator.compare(String(a), String(b));
}

function tableId(table: Element): string {
  return table.id || table.getAttribute('data-sort-id') || 'default';
}

// Record the active sort in state and reflect it on the header indicators.
function markSorted(table: Element, colIndex: number, dir: 'asc' | 'desc'): void {
  sortState[tableId(table)] = { colIndex, direction: dir };

  let tdPos = 0;
  $$('thead tr:first-child th', table).forEach((th) => {
    const span = Number.parseInt(th.getAttribute('colspan') || '1', 10);
    th.classList.remove('sorting_asc', 'sorting_desc', 'sorting');
    const isActive = colIndex >= tdPos && colIndex < tdPos + span;
    th.classList.add(isActive ? (dir === 'asc' ? 'sorting_asc' : 'sorting_desc') : 'sorting');
    tdPos += span;
  });
}

function reorderRows(tbody: Element, rows: Element[]): void {
  const fragment = document.createDocumentFragment();
  rows.forEach((row) => fragment.appendChild(row));
  tbody.appendChild(fragment);
}

function performSort(table: Element, colIndex: number): void {
  const state = sortState[tableId(table)];

  const dir: 'asc' | 'desc' =
    state && state.colIndex === colIndex && state.direction === 'asc' ? 'desc' : 'asc';

  const tbody = table.querySelector('tbody')!;
  let rows = Array.from(tbody.querySelectorAll('tr.t-file'));
  if (rows.length === 0) {
    markSorted(table, colIndex, dir);
    return;
  }

  if (state && state.colIndex === colIndex) {
    // Same column: the rows are already ordered by it, so flipping the
    // direction is a pure reversal — no value extraction, no comparisons.
    rows.reverse();
  } else {
    const childIndex = visibleChildIndex(rows[0], colIndex);
    const decorated = rows.map((row) => ({
      row,
      value: cachedSortValue(row, childIndex)
    }));

    const factor = dir === 'asc' ? 1 : -1;
    decorated.sort((a, b) => factor * compareValues(a.value, b.value));
    rows = decorated.map(({ row }) => row);
  }

  reorderRows(tbody, rows);
  applyRowWindow(table);
  markSorted(table, colIndex, dir);
}

// Above this row count a click-to-sort is slow enough (the browser re-lays-out
// the whole table) to be worth surfacing. Below it the sort is imperceptible
// and runs inline so small reports stay instant.
const SORT_OVERLAY_THRESHOLD = 500;

// A dim overlay that signals a slow re-sort. It leaves the table visible but
// dimmed and covers the page so stray clicks land on it rather than on rows
// that are about to move. Created lazily and reused across sorts.
let sortOverlay: HTMLElement | null = null;

function ensureSortOverlay(): HTMLElement {
  if (sortOverlay) return sortOverlay;
  const el = document.createElement('div');
  el.id = 'sort-overlay';
  el.innerHTML = '<span id="sort-overlay-label">Sorting…</span>';
  el.style.display = 'none';
  document.body.appendChild(el);
  sortOverlay = el;
  return el;
}

function showSortOverlay(): void {
  const el = ensureSortOverlay();
  el.style.transition = 'none';
  el.style.opacity = '1';
  el.style.display = 'flex';
}

function hideSortOverlay(): void {
  if (!sortOverlay) return;
  const el = sortOverlay;
  el.style.transition = 'opacity 0.15s';
  el.style.opacity = '0';
  setTimeout(() => { el.style.display = 'none'; }, 150);
}

// Sort on a header click. Small tables sort synchronously (instant); large ones
// show the overlay first and defer the work two frames, so the overlay is
// painted and absorbs stray clicks while the main thread blocks on the sort.
function sortTable(table: Element, colIndex: number): void {
  const rowCount = table.querySelectorAll('tbody tr.t-file').length;
  if (rowCount < SORT_OVERLAY_THRESHOLD) {
    performSort(table, colIndex);
    return;
  }

  showSortOverlay();
  requestAnimationFrame(() =>
    requestAnimationFrame(() => {
      performSort(table, colIndex);
      hideSortOverlay();
    })
  );
}

// Map a clicked <th> to the index of the (rightmost) <td> it spans, so that
// sorting a multi-column header sorts on its numeric (rightmost) column.
function thToTdIndex(table: Element, clickedTh: Element): number {
  let idx = 0;
  for (const th of $$('thead tr:first-child th', table)) {
    const span = Number.parseInt(th.getAttribute('colspan') || '1', 10);
    if (th === clickedTh) return idx + span - 1;
    idx += span;
  }
  return idx;
}

// Column index to sort on by default: the primary coverage column named by
// `SimpleCov.primary_coverage` (its cell carries a `cell--<type>-pct` class),
// falling back to the first coverage column when the primary isn't known or
// isn't shown. Returns null when the row has no coverage columns.
function primarySortColumn(row: Element, primaryCoverage?: string): number | null {
  const cells = Array.from(row.children);
  if (primaryCoverage) {
    const primary = cells.findIndex((cell) => cell.classList.contains(`cell--${primaryCoverage}-pct`));
    if (primary !== -1) return primary;
  }
  const first = cells.findIndex((cell) => cell.hasAttribute('data-order'));
  return first === -1 ? null : first;
}

// Restore the pre-1.0 default: sort each file list by its primary coverage
// column ascending, so the least-covered file is at the top. Records the
// sort state / indicator on that column so a later click on it toggles as
// usual. Runs during the initial render, while the loading overlay is shown,
// so it doesn't block user interaction. See #1171.
function applyDefaultSort(table: Element, primaryCoverage?: string): void {
  const tbody = table.querySelector('tbody');
  if (!tbody) return;

  const rows = Array.from(tbody.querySelectorAll('tr.t-file'));
  if (rows.length === 0) return;

  const colIndex = primarySortColumn(rows[0], primaryCoverage);
  if (colIndex === null) return;

  const decorated = rows.map((row) => ({
    row,
    value: cachedSortValue(row, colIndex)
  }));
  decorated.sort((a, b) => compareValues(a.value, b.value));

  reorderRows(tbody, decorated.map(({ row }) => row));
  markSorted(table, colIndex, 'asc');
}

export function setupTableSorting(primaryCoverage?: string): void {
  $$('table.file_list').forEach(table => {
    $$('thead tr:first-child th', table).forEach((th) => {
      th.classList.add('sorting');
      (th as HTMLElement).style.cursor = 'pointer';
      th.addEventListener('click', () => sortTable(table, thToTdIndex(table, th)));
    });

    applyDefaultSort(table, primaryCoverage);
    // Window before the first paint so huge reports never lay out in full.
    applyRowWindow(table);
  });
}
