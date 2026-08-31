
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

const collator = new Intl.Collator();

function compareValues(a: number | string, b: number | string): number {
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  return collator.compare(String(a), String(b));
}

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
    rows.reverse();
  } else {
    const childIndex = visibleChildIndex(rows[0], colIndex);
    rows = orderRows(rows, childIndex, dir);
  }

  reorderRows(tbody, rows);
  applyRowWindow(table);
  markSorted(table, colIndex, dir);
}

const SORT_OVERLAY_THRESHOLD = 500;

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

function thToTdIndex(table: Element, clickedTh: Element): number {
  let idx = 0;
  for (const th of $$('thead tr:first-child th', table)) {
    const span = Number.parseInt(th.getAttribute('colspan') || '1', 10);
    if (th === clickedTh) return idx + span - 1;
    idx += span;
  }
  return idx;
}

function primarySortColumn(row: Element, primaryCoverage?: string): number | null {
  const cells = Array.from(row.children);
  if (primaryCoverage) {
    const primary = cells.findIndex((cell) => cell.classList.contains(`cell--${primaryCoverage}-pct`));
    if (primary !== -1) return primary;
  }
  const first = cells.findIndex((cell) => cell.hasAttribute('data-order'));
  return first === -1 ? null : first;
}

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
    applyRowWindow(table);
  });
}
