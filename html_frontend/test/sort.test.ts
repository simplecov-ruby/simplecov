import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { setupTableSorting } from '../src/sort';
import { renderCoverageCells } from '../src/render_cells';

const HEADERS = '<th data-sort-key="file">File</th>' +
  '<th colspan="3" data-sort-key="line-total">Line</th>' +
  '<th colspan="3" data-sort-key="branch-total">Branch</th>';

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

const CRITERION_HEADERS = '<th data-sort-key="file">File</th>' +
  '<th data-sort-key="line-percent">Line %</th>' +
  '<th data-sort-key="line-covered">Covered Lines</th>' +
  '<th data-sort-key="line-total">Lines</th>' +
  '<th data-sort-key="branch-percent">Branch %</th>' +
  '<th data-sort-key="branch-covered">Covered Branches</th>' +
  '<th data-sort-key="branch-total">Branches</th>';

function tiedBranchRow(name: string, linePct: number, coveredBranches: number): string {
  return `<tr class="t-file"><td>${name}</td>` +
    `<td class="cell--line-pct" data-order="${linePct}">${linePct}%</td><td>1/</td><td>2</td>` +
    `<td class="cell--branch-pct" data-order="50">50%</td><td>${coveredBranches}/</td><td>4</td></tr>`;
}

const TIED_BRANCH_ROWS = [
  tiedBranchRow('lib/a.rb', 100, 1),
  tiedBranchRow('lib/z.rb', 50, 1),
  tiedBranchRow('lib/m.rb', 75, 2)
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

beforeEach(() => localStorage.clear());
afterEach(() => localStorage.clear());

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

    click(headerAt(table, 1));
    expect(names(table)).toEqual(['lib/b.rb', 'lib/c.rb', 'lib/a.rb']);
    expect(headerAt(table, 1).classList.contains('sorting_asc')).toBe(true);

    click(headerAt(table, 1));
    expect(names(table)).toEqual(['lib/a.rb', 'lib/c.rb', 'lib/b.rb']);
    expect(headerAt(table, 1).classList.contains('sorting_desc')).toBe(true);

    click(headerAt(table, 0));
    expect(names(table)).toEqual(['lib/a.rb', 'lib/b.rb', 'lib/c.rb']);

    click(headerAt(table, 1));
    expect(names(table)).toEqual(['lib/b.rb', 'lib/c.rb', 'lib/a.rb']);
  });

  test('restores the selected column and direction after a reload', () => {
    let table = buildTable(HEADERS, ROWS);
    setupTableSorting('line');

    click(headerAt(table, 2));
    click(headerAt(table, 2));
    expect(names(table)).toEqual(['lib/c.rb', 'lib/b.rb', 'lib/a.rb']);
    expect(localStorage.getItem('simplecov-sort')).toBe('{"column":"branch-total","direction":"desc"}');

    table = buildTable(HEADERS, ROWS);
    setupTableSorting('line');
    expect(names(table)).toEqual(['lib/c.rb', 'lib/b.rb', 'lib/a.rb']);
    expect(headerAt(table, 2).classList.contains('sorting_desc')).toBe(true);
  });

  test('preserves Covered Branches tie order across reloads in both directions', () => {
    let table = buildTable(CRITERION_HEADERS, TIED_BRANCH_ROWS);
    setupTableSorting('line');
    expect(names(table)).toEqual(['lib/z.rb', 'lib/m.rb', 'lib/a.rb']);

    click(headerAt(table, 5));
    const ascending = names(table);
    expect(ascending).toEqual(['lib/a.rb', 'lib/z.rb', 'lib/m.rb']);

    table = buildTable(CRITERION_HEADERS, TIED_BRANCH_ROWS);
    setupTableSorting('line');
    expect(names(table)).toEqual(ascending);

    click(headerAt(table, 5));
    const descending = names(table);
    expect(descending).toEqual(['lib/m.rb', 'lib/z.rb', 'lib/a.rb']);

    table = buildTable(CRITERION_HEADERS, TIED_BRANCH_ROWS);
    setupTableSorting('line');
    expect(names(table)).toEqual(descending);
  });

  test('falls back for stale or malformed preferences', () => {
    localStorage.setItem('simplecov-sort', '{"column":"method-total","direction":"desc"}');
    let table = buildTable(HEADERS, ROWS);
    setupTableSorting('line');
    expect(names(table)).toEqual(['lib/c.rb', 'lib/b.rb', 'lib/a.rb']);

    for (const preference of ['not json', '{}', '{"column":"file","direction":"sideways"}']) {
      localStorage.setItem('simplecov-sort', preference);
      table = buildTable(HEADERS, ROWS);
      setupTableSorting('branch');
      expect(names(table)).toEqual(['lib/a.rb', 'lib/b.rb', 'lib/c.rb']);
    }
  });

  test('keeps sorting when localStorage is unavailable', () => {
    const descriptor = Object.getOwnPropertyDescriptor(window, 'localStorage')!;
    Object.defineProperty(window, 'localStorage', {
      configurable: true,
      get() {
        throw new Error('storage disabled');
      }
    });

    try {
      const table = buildTable(HEADERS, ROWS);
      setupTableSorting('line');
      click(headerAt(table, 0));
      expect(names(table)).toEqual(['lib/a.rb', 'lib/b.rb', 'lib/c.rb']);
    } finally {
      Object.defineProperty(window, 'localStorage', descriptor);
    }
  });

  test('rows missing the sorted cell and hidden cells are tolerated', () => {
    const table = buildTable('<th>File</th><th>A</th><th>B</th><th>C</th><th>D</th>', [
      '<tr class="t-file"><td>lib/full.rb</td><td style="display: none">skip</td><td data-order="2">2</td><td>x</td><td>y</td></tr>',
      '<tr class="t-file"><td>lib/short.rb</td><td data-order="1">1</td></tr>'
    ]);
    setupTableSorting();

    click(headerAt(table, 3));
    expect(names(table)).toEqual(['lib/full.rb', 'lib/short.rb']);

    click(headerAt(table, 4));
    expect(headerAt(table, 4).classList.contains('sorting_asc')).toBe(true);
    expect(names(table)).toEqual(['lib/full.rb', 'lib/short.rb']);
  });

  test('sorts the rendered count columns numerically, not by grouped text', () => {
    const countRow = (name: string, covered: number, total: number): string =>
      `<tr class="t-file"><td>${name}</td>${renderCoverageCells(100, covered, total, 'line', false)}</tr>`;
    const table = buildTable(
      '<th data-sort-key="file">File</th><th data-sort-key="line-percent">Line %</th>' +
      '<th data-sort-key="line-covered">Covered</th><th data-sort-key="line-total">Lines</th>',
      [countRow('lib/big.rb', 1250, 1250), countRow('lib/small.rb', 999, 999)]
    );
    setupTableSorting();

    click(headerAt(table, 3));
    expect(names(table)).toEqual(['lib/small.rb', 'lib/big.rb']);

    click(headerAt(table, 2));
    expect(names(table)).toEqual(['lib/small.rb', 'lib/big.rb']);
  });

  test('a header detached after wiring falls through to the column count', () => {
    const table = buildTable(HEADERS, ROWS);
    setupTableSorting('line');
    const th = headerAt(table, 0);
    th.remove();
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

    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve(undefined))));
    expect(names(table)[0]).toBe('lib/f000.rb');
    expect(overlay.style.opacity).toBe('0');
    await new Promise((resolve) => setTimeout(resolve, 220));
    expect(overlay.style.display).toBe('none');

    click(headerAt(table, 1));
    expect(document.querySelectorAll('#sort-overlay').length).toBe(1);
    expect(overlay.style.display).toBe('flex');
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve(undefined))));
    await new Promise((resolve) => setTimeout(resolve, 220));
    expect(overlay.style.display).toBe('none');
  });
});

describe('by-tests secondary sort', () => {
  const TRACKED_HEADERS = '<th data-sort-key="file">File</th>' +
    '<th data-sort-key="line-percent">Line %</th>' +
    '<th data-sort-key="line-covered">Covered</th>' +
    '<th data-sort-key="line-total">Lines</th>';

  function trackedRow(name: string, pct: string, byTests: string): string {
    return `<tr class="t-file"><td>${name}</td>` +
      `<td class="cell--line-pct" data-order="${pct}" data-order-2="${byTests}">${pct}%</td>` +
      `<td>1/</td><td>2</td></tr>`;
  }

  const TRACKED_ROWS = [
    trackedRow('lib/a.rb', '100.00', '80.00'),
    trackedRow('lib/b.rb', '100.00', '90.00'),
    trackedRow('lib/c.rb', '50.00', '50.00')
  ];

  test('descending ranks the higher by-tests percent first among ties', () => {
    const table = buildTable(TRACKED_HEADERS, TRACKED_ROWS);
    setupTableSorting('line');
    click(headerAt(table, 1));
    expect(names(table)).toEqual(['lib/b.rb', 'lib/a.rb', 'lib/c.rb']);
  });

  test('ascending ranks the lower by-tests percent first among ties', () => {
    const table = buildTable(TRACKED_HEADERS, TRACKED_ROWS);
    setupTableSorting('line');
    expect(names(table)).toEqual(['lib/c.rb', 'lib/a.rb', 'lib/b.rb']);
  });

  test('falls through to the filename when the by-tests percents tie too', () => {
    const table = buildTable(TRACKED_HEADERS, [
      trackedRow('lib/z.rb', '100.00', '90.00'),
      trackedRow('lib/a.rb', '100.00', '90.00')
    ]);
    setupTableSorting('line');
    expect(names(table)).toEqual(['lib/a.rb', 'lib/z.rb']);
  });
});
