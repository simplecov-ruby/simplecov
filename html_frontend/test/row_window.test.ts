// Ports the large-report windowing behavior: only the first 1000
// filter-matched rows stay visible, the rest sit behind a "Show all"
// affordance row. See #1171.
import { describe, expect, test } from 'bun:test';
import { applyRowWindow } from '../src/row_window';

function buildTable(rowCount: number): HTMLTableElement {
  const table = document.createElement('table');
  const tbody = document.createElement('tbody');
  table.appendChild(tbody);
  const rows: string[] = [];
  for (let i = 0; i < rowCount; i++) {
    rows.push(`<tr class="t-file"><td>file${i}.rb</td><td>${i}</td></tr>`);
  }
  tbody.innerHTML = rows.join('');
  document.body.appendChild(table);
  return table;
}

function windowHiddenCount(table: Element): number {
  return table.querySelectorAll('tr.t-file.t-window-hidden').length;
}

function affordance(table: Element): HTMLElement | null {
  return table.querySelector('tr.t-show-all') as HTMLElement | null;
}

describe('applyRowWindow', () => {
  test('bails on a table without a tbody', () => {
    const table = document.createElement('table');
    applyRowWindow(table);
    expect(affordance(table)).toBeNull();
  });

  test('leaves small tables unwindowed with no affordance', () => {
    document.body.innerHTML = '';
    const table = buildTable(3);
    applyRowWindow(table);
    expect(windowHiddenCount(table)).toBe(0);
    expect(affordance(table)).toBeNull();
  });

  test('windows matched rows past 1000 behind a Show all affordance', () => {
    document.body.innerHTML = '';
    const table = buildTable(1105);
    const rows = Array.from(table.querySelectorAll('tr.t-file')) as HTMLElement[];
    // Filter-hidden rows don't count toward the window.
    for (const row of rows.slice(0, 5)) row.style.display = 'none';

    applyRowWindow(table);

    expect(windowHiddenCount(table)).toBe(100);
    for (const row of rows.slice(0, 5)) expect(row.classList.contains('t-window-hidden')).toBe(false);

    const showAll = affordance(table)!;
    expect(showAll.style.display).toBe('');
    expect((showAll.firstElementChild as HTMLTableCellElement).colSpan).toBe(2);
    expect(showAll.textContent).toContain('Showing the first 1,000 of 1,100 files.');
    expect(table.querySelector('tbody')!.lastElementChild).toBe(showAll);

    // Re-applying reuses the affordance row instead of stacking a second one.
    applyRowWindow(table);
    expect(table.querySelectorAll('tr.t-show-all').length).toBe(1);
  });

  test('Show all unwindows the table for the rest of the session', () => {
    document.body.innerHTML = '';
    const table = buildTable(1010);
    applyRowWindow(table);
    expect(windowHiddenCount(table)).toBe(10);

    const link = affordance(table)!.querySelector('a.t-show-all__link')!;
    link.dispatchEvent(new Event('click', { bubbles: true, cancelable: true }));

    expect(windowHiddenCount(table)).toBe(0);
    expect(affordance(table)!.style.display).toBe('none');

    // Later re-applies (a re-sort or re-filter) keep the window disabled.
    applyRowWindow(table);
    expect(windowHiddenCount(table)).toBe(0);
    expect(affordance(table)!.style.display).toBe('none');
  });

  test('hides the affordance again when filtering brings the table under the limit', () => {
    document.body.innerHTML = '';
    const table = buildTable(1005);
    applyRowWindow(table);
    expect(affordance(table)!.style.display).toBe('');
    expect(windowHiddenCount(table)).toBe(5);

    const rows = Array.from(table.querySelectorAll('tr.t-file')) as HTMLElement[];
    for (const row of rows.slice(0, 10)) row.style.display = 'none';
    applyRowWindow(table);

    expect(windowHiddenCount(table)).toBe(0);
    expect(affordance(table)!.style.display).toBe('none');
  });
});
