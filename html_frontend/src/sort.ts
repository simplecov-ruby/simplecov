// Column sorting for the file-list tables, including click-to-sort wiring and
// the per-table sort-direction state.

import { $$ } from './dom';
import { applyRowWindow } from './row_window';
import { readPreference, writePreference } from './prefs';

interface SortEntry {
  colIndex: number;
  direction: 'asc' | 'desc';
}

interface SortPreference {
  column: string;
  direction: 'asc' | 'desc';
}

const sortState = new WeakMap<Element, SortEntry>();
const SORT_STORAGE_KEY = 'simplecov-sort';

// A stale or malformed value is ignored so reports with a different set of
// coverage criteria still get their normal default. Storage itself is read
// and written through the shared guard the display modes use.
function readSortPreference(): SortPreference | null {
  const raw = readPreference(SORT_STORAGE_KEY);
  if (!raw) return null;

  try {
    const value = JSON.parse(raw) as Partial<SortPreference>;
    if (typeof value.column !== 'string' || !value.column) return null;
    if (value.direction !== 'asc' && value.direction !== 'desc') return null;
    return { column: value.column, direction: value.direction };
  } catch {
    return null;
  }
}

function writeSortPreference(preference: SortPreference): void {
  writePreference(SORT_STORAGE_KEY, JSON.stringify(preference));
}

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
const rowTiebreakCache = new WeakMap<Element, Map<number, number | null>>();

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

// A tracked run's coverage cells carry the by-tests percent as data-order-2,
// the tie level between the sorted value and the filename: equal coverage
// ranks by how much of it recorded tests produced. Cells without the
// attribute (untracked runs, count columns) return null and tie neutrally.
// A stored null is a valid cache hit, distinguished from a missing entry.
function cachedTiebreakValue(row: Element, childIndex: number | null): number | null {
  if (childIndex === null) return null;
  let cache = rowTiebreakCache.get(row);
  if (!cache) {
    cache = new Map();
    rowTiebreakCache.set(row, cache);
  }
  const hit = cache.get(childIndex);
  if (hit !== undefined) return hit;
  const order = (row.children[childIndex] ?? null)?.getAttribute('data-order-2');
  const value = order == null ? null : Number.parseFloat(order);
  cache.set(childIndex, value);
  return value;
}

function compareTiebreaks(a: number | null, b: number | null): number {
  return a === null || b === null ? 0 : a - b;
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

// Sort ties by the by-tests percent (when the cell carries one), then by
// file name, so applying a saved preference to the report's original row
// order produces exactly the same result as the user's click on an
// already-sorted table. The direction applies to the composite key, which
// keeps the same-column reversal optimization valid.
function orderRows(rows: Element[], childIndex: number | null, dir: 'asc' | 'desc'): Element[] {
  const decorated = rows.map((row) => ({
    row,
    value: cachedSortValue(row, childIndex),
    tiebreak: cachedTiebreakValue(row, childIndex),
    filename: cachedSortValue(row, 0)
  }));
  const factor = dir === 'asc' ? 1 : -1;
  decorated.sort((a, b) => factor * (
    compareValues(a.value, b.value) ||
    compareTiebreaks(a.tiebreak, b.tiebreak) ||
    compareValues(a.filename, b.filename)
  ));
  return decorated.map(({ row }) => row);
}

// Record the active sort in state and reflect it on the header indicators.
function markSorted(table: Element, colIndex: number, dir: 'asc' | 'desc'): void {
  sortState.set(table, { colIndex, direction: dir });

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

function performSort(table: Element, colIndex: number, dir: 'asc' | 'desc'): void {
  const state = sortState.get(table);

  const tbody = table.querySelector('tbody')!;
  let rows = Array.from(tbody.querySelectorAll('tr.t-file'));
  if (rows.length === 0) {
    markSorted(table, colIndex, dir);
    return;
  }

  if (state && state.colIndex === colIndex && state.direction !== dir) {
    // Same column: both the primary value and filename tie-breaker reverse,
    // so flipping the direction is a pure reversal.
    rows.reverse();
  } else {
    const childIndex = visibleChildIndex(rows[0], colIndex);
    rows = orderRows(rows, childIndex, dir);
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
function sortTable(table: Element, header: Element): void {
  const colIndex = thToTdIndex(table, header);
  const state = sortState.get(table);
  const direction: 'asc' | 'desc' =
    state && state.colIndex === colIndex && state.direction === 'asc' ? 'desc' : 'asc';
  const column = header.getAttribute('data-sort-key');
  if (column) writeSortPreference({ column, direction });

  const rowCount = table.querySelectorAll('tbody tr.t-file').length;
  if (rowCount < SORT_OVERLAY_THRESHOLD) {
    performSort(table, colIndex, direction);
    return;
  }

  showSortOverlay();
  requestAnimationFrame(() =>
    requestAnimationFrame(() => {
      performSort(table, colIndex, direction);
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
function applyInitialSort(table: Element, primaryCoverage: string | undefined, preference: SortPreference | null): void {
  const tbody = table.querySelector('tbody');
  if (!tbody) return;

  const rows = Array.from(tbody.querySelectorAll('tr.t-file'));
  if (rows.length === 0) return;

  const preferredHeader = preference && $$('thead tr:first-child th', table)
    .find((header) => header.getAttribute('data-sort-key') === preference.column);
  const colIndex = preferredHeader
    ? thToTdIndex(table, preferredHeader)
    : primarySortColumn(rows[0], primaryCoverage);
  if (colIndex === null) return;
  const direction = preferredHeader ? preference!.direction : 'asc';

  reorderRows(tbody, orderRows(rows, colIndex, direction));
  markSorted(table, colIndex, direction);
}

export function setupTableSorting(primaryCoverage?: string): void {
  const preference = readSortPreference();
  $$('table.file_list').forEach(table => {
    $$('thead tr:first-child th', table).forEach((th) => {
      th.classList.add('sorting');
      (th as HTMLElement).style.cursor = 'pointer';
      th.addEventListener('click', () => sortTable(table, th));
    });

    applyInitialSort(table, primaryCoverage, preference);
    // Window before the first paint so huge reports never lay out in full.
    applyRowWindow(table);
  });
}
