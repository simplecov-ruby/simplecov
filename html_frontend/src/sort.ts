
import { $$ } from './dom';
import { applyRowWindow } from './row_window';
import { readPreference, writePreference } from './prefs';

interface SortEntry {
  colIndex: number;
  direction: 'asc' | 'desc';
}

interface SortPreference {
  column: unknown;
  direction: 'asc' | 'desc';
}

const sortState = new WeakMap<Element, SortEntry>();
const SORT_STORAGE_KEY = 'simplecov-sort';

function storedPreference(): Partial<SortPreference> {
  try {
    return JSON.parse(String(readPreference(SORT_STORAGE_KEY))) ?? {};
  } catch {
    return {};
  }
}

function readSortPreference(): SortPreference | null {
  const value = storedPreference();
  if (value.direction !== 'asc' && value.direction !== 'desc') return null;
  return { column: value.column, direction: value.direction };
}

function writeSortPreference(preference: SortPreference): void {
  writePreference(SORT_STORAGE_KEY, JSON.stringify(preference));
}

function visibleChildIndex(row: Element, index: number): number {
  let visible = 0;
  const children = row.children;
  for (let i = 0; i < children.length; i++) {
    if ((children[i] as HTMLElement).style.display === 'none') continue;
    if (visible === index) return i;
    visible += 1;
  }
  return -1;
}

function getSortValue(td: Element | undefined): number | string {
  if (!td) return '';
  const order = td.getAttribute('data-order');
  if (order !== null) return Number.parseFloat(order);
  const text = td.textContent!.trim();
  const num = Number.parseFloat(text);
  return Number.isNaN(num) ? text : num;
}

function tiebreakValue(td: Element | undefined): number {
  return Number.parseFloat(String(td?.getAttribute('data-order-2')));
}

const collator = new Intl.Collator(undefined, { sensitivity: 'accent' });

function compareValues(a: number | string, b: number | string): number {
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  return collator.compare(String(a), String(b));
}

interface Decorated {
  row: Element;
  value: number | string;
  tiebreak: number;
  filename: number | string;
}

function orderRows(rows: Element[], childIndex: number, dir: 'asc' | 'desc'): Element[] {
  const decorated = rows.map((row) => ({
    row,
    value: getSortValue(row.children[childIndex]),
    tiebreak: tiebreakValue(row.children[childIndex]),
    filename: getSortValue(row.children[0])
  }));
  const ascending = (a: Decorated, b: Decorated): number =>
    compareValues(a.value, b.value) ||
    (a.tiebreak - b.tiebreak) ||
    compareValues(a.filename, b.filename);
  decorated.sort(dir === 'asc' ? ascending : (a, b) => ascending(b, a));
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

  if (state && state.colIndex === colIndex) {
    rows.reverse();
  } else {
    rows = orderRows(rows, visibleChildIndex(rows[0], colIndex), dir);
  }

  reorderRows(tbody, rows);
  applyRowWindow(table);
  markSorted(table, colIndex, dir);
}

const SORT_OVERLAY_THRESHOLD = 500;

let sortOverlay: HTMLElement | null = null;

function showSortOverlay(): HTMLElement {
  if (!sortOverlay) {
    sortOverlay = document.createElement('div');
    sortOverlay.id = 'sort-overlay';
    sortOverlay.innerHTML = '<span id="sort-overlay-label">Sorting…</span>';
    document.body.appendChild(sortOverlay);
  }
  const el = sortOverlay;
  el.style.transition = 'none';
  el.style.opacity = '1';
  el.style.display = 'flex';
  return el;
}

function hideSortOverlay(el: HTMLElement): void {
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

  const overlay = showSortOverlay();
  requestAnimationFrame(() =>
    requestAnimationFrame(() => {
      performSort(table, colIndex, direction);
      hideSortOverlay(overlay);
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
  const primary = cells.findIndex((cell) => cell.classList.contains(`cell--${primaryCoverage}-pct`));
  const first = primary === -1 ? cells.findIndex((cell) => cell.hasAttribute('data-order')) : primary;
  return first === -1 ? null : first;
}

function applyInitialSort(table: Element, primaryCoverage: string | undefined, preference: SortPreference | null): void {
  const tbody = table.querySelector('tbody');
  if (!tbody) return;

  const rows = Array.from(tbody.querySelectorAll('tr.t-file'));
  if (rows.length === 0) return;

  const preferredHeader = preference && $$('thead tr:first-child th[data-sort-key]', table)
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
