// Windows large file lists: only the first MAX_VISIBLE_ROWS rows that match
// the active filters are shown, with the rest behind a "Show all" row. The
// browser lays out every visible table row after a re-sort, which froze
// multi-thousand-file reports for seconds. Windowing is presentation only:
// sorting, filtering, and the totals row still cover every file. See #1171.
//
// Filters hide rows via inline style.display (see filter.ts). The window uses
// a class instead, so the two mechanisms stay independent.

import { fmtNum } from './format';

const MAX_VISIBLE_ROWS = 1000;
const HIDDEN_CLASS = 't-window-hidden';

// Tables whose "Show all" was clicked. Session-only by design: reopening the
// report re-windows, which is the fast default.
const windowDisabled = new WeakSet<Element>();

function affordanceRow(tbody: Element, columns: number): HTMLElement {
  let row = tbody.querySelector('tr.t-show-all') as HTMLElement | null;
  if (!row) {
    row = document.createElement('tr');
    row.className = 't-show-all';
    const td = document.createElement('td');
    td.colSpan = columns;
    row.appendChild(td);
    // The listener lives on the row, not the link, so it survives the
    // innerHTML refresh of the cell on every re-apply.
    row.addEventListener('click', (e) => {
      e.preventDefault();
      windowDisabled.add(tbody);
      applyRowWindow(tbody.closest('table')!);
    });
    tbody.appendChild(row);
  }
  return row;
}

// Re-window a table after its rows were reordered or refiltered. Hides
// filter-matched rows beyond MAX_VISIBLE_ROWS and maintains the "Show all"
// affordance after the last visible row.
export function applyRowWindow(table: Element): void {
  const tbody = table.querySelector('tbody');
  if (!tbody) return;

  const rows = tbody.querySelectorAll('tr.t-file');
  const disabled = windowDisabled.has(tbody);
  let matched = 0;
  rows.forEach((row) => {
    const hiddenByFilter = (row as HTMLElement).style.display === 'none';
    if (!hiddenByFilter) matched += 1;
    row.classList.toggle(HIDDEN_CLASS, !disabled && !hiddenByFilter && matched > MAX_VISIBLE_ROWS);
  });

  if (disabled || matched <= MAX_VISIBLE_ROWS) {
    const existing = tbody.querySelector('tr.t-show-all') as HTMLElement | null;
    if (existing) existing.style.display = 'none';
    return;
  }

  const row = affordanceRow(tbody, rows[0].children.length);
  row.style.display = '';
  row.firstElementChild!.innerHTML =
    `Showing the first ${fmtNum(MAX_VISIBLE_ROWS)} of ${fmtNum(matched)} files. ` +
    '<a href="#" class="t-show-all__link">Show all</a>';
  tbody.appendChild(row); // keep it below the rows after a re-sort
}
