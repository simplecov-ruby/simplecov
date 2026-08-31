
import { fmtNum } from './format';

const MAX_VISIBLE_ROWS = 1000;
const HIDDEN_CLASS = 't-window-hidden';

const windowDisabled = new WeakSet<Element>();

function affordanceRow(tbody: Element, columns: number): HTMLElement {
  let row = tbody.querySelector('tr.t-show-all') as HTMLElement | null;
  if (!row) {
    row = document.createElement('tr');
    row.className = 't-show-all';
    const td = document.createElement('td');
    td.colSpan = columns;
    row.appendChild(td);
    row.addEventListener('click', (e) => {
      e.preventDefault();
      windowDisabled.add(tbody);
      applyRowWindow(tbody.closest('table')!);
    });
    tbody.appendChild(row);
  }
  return row;
}

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
  tbody.appendChild(row);
}
