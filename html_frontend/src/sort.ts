// Column sorting for the file-list tables, including click-to-sort wiring and
// the per-table sort-direction state.

import { $$ } from './dom';

interface SortEntry {
  colIndex: number;
  direction: 'asc' | 'desc';
}

const sortState: Record<string, SortEntry> = {};

function getVisibleChild(row: Element, index: number): Element | null {
  const visible = Array.from(row.children).filter((c) => (c as HTMLElement).style.display !== 'none');
  return visible[index] ?? null;
}

function getSortValue(td: Element | null): number | string {
  if (!td) return '';
  const order = td.getAttribute('data-order');
  if (order !== null) return Number.parseFloat(order);
  const text = (td.textContent || '').trim();
  const num = Number.parseFloat(text);
  return Number.isNaN(num) ? text.toLowerCase() : num;
}

// Compare two cell values numerically when both are numbers, otherwise
// as case-insensitive strings.
function compareValues(a: number | string, b: number | string): number {
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  return String(a).localeCompare(String(b));
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

function sortTable(table: Element, colIndex: number): void {
  const state = sortState[tableId(table)];

  const dir: 'asc' | 'desc' =
    state && state.colIndex === colIndex && state.direction === 'asc' ? 'desc' : 'asc';

  const tbody = table.querySelector('tbody')!;
  const rows = Array.from(tbody.querySelectorAll('tr.t-file')).map((row) => ({
    row,
    value: getSortValue(getVisibleChild(row, colIndex))
  }));

  rows.sort((a, b) => (dir === 'asc' ? 1 : -1) * compareValues(a.value, b.value));

  reorderRows(tbody, rows.map(({ row }) => row));
  markSorted(table, colIndex, dir);
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
    value: getSortValue(row.children[colIndex] ?? null)
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
  });
}
