// Click-to-sort behavior of the file-list tables: the default
// primary-coverage sort, direction toggling, sort-value extraction and
// caching, colspan-aware header mapping, and the slow-sort overlay that
// large tables show while the main thread blocks.
import { describe, expect, test } from 'bun:test';
import { setupTableSorting } from '../src/sort';

// File / Line Coverage (3 cols) / Branch Coverage (3 cols), like the real
// report. The rightmost cell of each coverage group holds the totals count,
// so clicking a group header sorts by that numeric cell.
const HEADERS = '<th>File</th><th colspan="3">Line</th><th colspan="3">Branch</th>';

function coverageRow(name: string, linePct: string, lines: number, branchPct: string, branches: number): string {
  return (
    `<tr class="t-file"><td>${name}</td>` +
    `<td class="cell--line-pct" data-order="${linePct}">${linePct}%</td><td>0/</td><td>${lines}</td>` +
    `<td class="cell--branch-pct" data-order="${branchPct}">${branchPct}%</td><td>0/</td><td>${branches}</td></tr>`
  );
}

const ROWS = [
  coverageRow('lib/c.rb', '50.00', 4, '100.00', 9),
  coverageRow('lib/a.rb', '100.00', 10, '25.00', 2),
  coverageRow('lib/b.rb', '75.00', 2, '50.00', 4)
];

function buildTable(headers: string, rows: string[]): HTMLTableElement {
  document.body.innerHTML = `
    <table class="file_list">
      <thead><tr>${headers}</tr></thead>
      <tbody>${rows.join('')}</tbody>
    </table>`;
  return document.querySelector('table.file_list') as HTMLTableElement;
}

function names(table: Element): string[] {
  return Array.from(table.querySelectorAll('tbody tr.t-file td:first-child')).map((td) =>
    (td.textContent || '').trim()
  );
}

function headerAt(table: Element, index: number): HTMLElement {
  return table.querySelectorAll('thead tr:first-child th')[index] as HTMLElement;
}

function click(el: Element): void {
  el.dispatchEvent(new Event('click', { bubbles: true, cancelable: true }));
}

describe('default sort', () => {
  test('sorts by the primary coverage column ascending and marks its header', () => {
    const table = buildTable(HEADERS, ROWS);
    setupTableSorting('branch');
    expect(names(table)).toEqual(['lib/a.rb', 'lib/b.rb', 'lib/c.rb']);

    expect(headerAt(table, 2).classList.contains('sorting_asc')).toBe(true);
    expect(headerAt(table, 0).classList.contains('sorting')).toBe(true);
    expect(headerAt(table, 1).classList.contains('sorting')).toBe(true);
    expect(headerAt(table, 0).style.cursor).toBe('pointer');
  });

  test('falls back to the first sortable column when the primary is not shown', () => {
    const table = buildTable(HEADERS, ROWS);
    setupTableSorting('method');
    expect(names(table)).toEqual(['lib/c.rb', 'lib/b.rb', 'lib/a.rb']);
  });

  test('falls back to the first sortable column when no primary is named', () => {
    const table = buildTable(HEADERS, ROWS);
    setupTableSorting();
    expect(names(table)).toEqual(['lib/c.rb', 'lib/b.rb', 'lib/a.rb']);
  });

  test('leaves tables without sortable cells in document order', () => {
    const table = buildTable('<th>File</th>', [
      '<tr class="t-file"><td>lib/z.rb</td></tr>',
      '<tr class="t-file"><td>lib/a.rb</td></tr>'
    ]);
    setupTableSorting();
    expect(names(table)).toEqual(['lib/z.rb', 'lib/a.rb']);
  });

  test('tolerates tables without a tbody or without rows', () => {
    document.body.innerHTML = `
      <table class="file_list" id="headless"><thead><tr><th>File</th></tr></thead></table>
      <table class="file_list" id="empty"><thead><tr><th>File</th></tr></thead><tbody></tbody></table>`;
    setupTableSorting();

    // A click on the empty table still records the sort direction.
    const emptyTh = document.querySelector('#empty th') as HTMLElement;
    click(emptyTh);
    expect(emptyTh.classList.contains('sorting_asc')).toBe(true);
  });
});

describe('click sorting', () => {
  test('toggles direction on repeat clicks and switches columns', () => {
    const table = buildTable(HEADERS, ROWS);
    setupTableSorting('line');
    expect(names(table)).toEqual(['lib/c.rb', 'lib/b.rb', 'lib/a.rb']);

    // Clicking a colspan group sorts its rightmost cell: total lines.
    click(headerAt(table, 1));
    expect(names(table)).toEqual(['lib/b.rb', 'lib/c.rb', 'lib/a.rb']);
    expect(headerAt(table, 1).classList.contains('sorting_asc')).toBe(true);

    // Same column again: pure reversal to descending.
    click(headerAt(table, 1));
    expect(names(table)).toEqual(['lib/a.rb', 'lib/c.rb', 'lib/b.rb']);
    expect(headerAt(table, 1).classList.contains('sorting_desc')).toBe(true);

    // File names sort as case-insensitive strings.
    click(headerAt(table, 0));
    expect(names(table)).toEqual(['lib/a.rb', 'lib/b.rb', 'lib/c.rb']);

    // Back to the line column: values now come from the per-row cache.
    click(headerAt(table, 1));
    expect(names(table)).toEqual(['lib/b.rb', 'lib/c.rb', 'lib/a.rb']);
  });

  test('rows missing the sorted cell and hidden cells are tolerated', () => {
    const table = buildTable('<th>File</th><th>A</th><th>B</th><th>C</th><th>D</th>', [
      '<tr class="t-file"><td>lib/full.rb</td><td style="display: none">skip</td><td data-order="2">2</td><td>x</td><td>y</td></tr>',
      '<tr class="t-file"><td>lib/short.rb</td><td data-order="1">1</td></tr>'
    ]);
    setupTableSorting();

    // Column 3 resolves through the hidden cell to child index 4; the short
    // row has no such cell and sorts as the empty string.
    click(headerAt(table, 3));
    expect(names(table)).toEqual(['lib/short.rb', 'lib/full.rb']);

    // A column index beyond every visible cell sorts nothing but still
    // flips the header indicator.
    click(headerAt(table, 4));
    expect(headerAt(table, 4).classList.contains('sorting_asc')).toBe(true);
    expect(names(table)).toEqual(['lib/short.rb', 'lib/full.rb']);
  });

  test('a header detached after wiring falls through to the column count', () => {
    const table = buildTable(HEADERS, ROWS);
    setupTableSorting('line');
    const th = headerAt(table, 0);
    th.remove();
    // The listener still fires; thToTdIndex no longer finds the th and falls
    // through to the remaining column count (6), which here lands on the
    // branch-total cell.
    click(th);
    expect(names(table)).toEqual(['lib/a.rb', 'lib/b.rb', 'lib/c.rb']);
  });
});

describe('slow-sort overlay', () => {
  test('large tables sort behind a dimming overlay that fades back out', async () => {
    const rows: string[] = [];
    for (let i = 0; i < 500; i++) {
      const n = String(i).padStart(3, '0');
      rows.push(`<tr class="t-file"><td>lib/f${n}.rb</td><td data-order="${500 - i}">${500 - i}</td></tr>`);
    }
    const table = buildTable('<th>File</th><th>Line</th>', rows);
    setupTableSorting();
    expect(names(table)[0]).toBe('lib/f499.rb'); // default sort by data-order

    click(headerAt(table, 0));
    const overlay = document.getElementById('sort-overlay') as HTMLElement;
    expect(overlay.style.display).toBe('flex');
    expect(overlay.style.opacity).toBe('1');
    expect(overlay.textContent).toContain('Sorting…');

    // The sort itself runs two frames later, then the overlay fades out.
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve(undefined))));
    expect(names(table)[0]).toBe('lib/f000.rb');
    expect(overlay.style.opacity).toBe('0');
    await new Promise((resolve) => setTimeout(resolve, 220));
    expect(overlay.style.display).toBe('none');

    // A second slow sort reuses the same overlay element.
    click(headerAt(table, 1));
    expect(document.querySelectorAll('#sort-overlay').length).toBe(1);
    expect(overlay.style.display).toBe('flex');
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve(undefined))));
    await new Promise((resolve) => setTimeout(resolve, 220));
    expect(overlay.style.display).toBe('none');
  });
});
