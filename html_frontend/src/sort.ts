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

function sortTable(table: Element, colIndex: number): void {
  const tableId = table.id || table.getAttribute('data-sort-id') || 'default';
  const state = sortState[tableId];

  const dir: 'asc' | 'desc' =
    state && state.colIndex === colIndex && state.direction === 'asc' ? 'desc' : 'asc';
  sortState[tableId] = { colIndex, direction: dir };

  const tbody = table.querySelector('tbody')!;
  const rows = Array.from(tbody.querySelectorAll('tr.t-file')).map((row) => ({
    row,
    value: getSortValue(getVisibleChild(row, colIndex))
  }));

  rows.sort((a, b) => {
    const aVal = a.value;
    const bVal = b.value;
    let cmp: number;
    if (typeof aVal === 'number' && typeof bVal === 'number') {
      cmp = aVal - bVal;
    } else {
      cmp = String(aVal).localeCompare(String(bVal));
    }
    return dir === 'asc' ? cmp : -cmp;
  });

  const fragment = document.createDocumentFragment();
  rows.forEach(({ row }) => fragment.appendChild(row));
  tbody.appendChild(fragment);

  // Update sort indicators
  let tdPos = 0;
  $$('thead tr:first-child th', table).forEach((th) => {
    const span = Number.parseInt(th.getAttribute('colspan') || '1', 10);
    th.classList.remove('sorting_asc', 'sorting_desc', 'sorting');
    const isActive = colIndex >= tdPos && colIndex < tdPos + span;
    th.classList.add(isActive ? (dir === 'asc' ? 'sorting_asc' : 'sorting_desc') : 'sorting');
    tdPos += span;
  });
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

export function setupTableSorting(): void {
  $$('table.file_list').forEach(table => {
    $$('thead tr:first-child th', table).forEach((th) => {
      th.classList.add('sorting');
      (th as HTMLElement).style.cursor = 'pointer';
      th.addEventListener('click', () => sortTable(table, thToTdIndex(table, th)));
    });
  });
}
