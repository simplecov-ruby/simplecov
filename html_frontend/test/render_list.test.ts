import { beforeAll, describe, expect, test } from 'bun:test';
import { fileId, precomputeFileIds } from '../src/format';
import { renderFileList } from '../src/render_list';
import type { FileCoverage, ProductionData, StatGroup } from '../src/types';

const FULL = 'lib/full.rb';
const BARE = 'lib/<bare>.rb';

beforeAll(async () => {
  await precomputeFileIds([FULL, BARE]);
});

const stats: StatGroup = {
  lines: { covered: 8, missed: 2, total: 10, percent: 80, strength: 1 },
  branches: { covered: 3, missed: 1, total: 4, percent: 75, strength: 1 },
  methods: { covered: 1, missed: 1, total: 2, percent: 50, strength: 1 }
};

const fullCoverage: FileCoverage = {
  source: ['a'],
  lines_covered_percent: 80,
  covered_lines: 8,
  total_lines: 10,
  branches_covered_percent: 75,
  covered_branches: 3,
  total_branches: 4,
  methods_covered_percent: 50,
  covered_methods: 1,
  total_methods: 2
};

const bareCoverage: FileCoverage = { source: [] };

function parse(html: string): HTMLElement {
  const el = document.createElement('div');
  el.innerHTML = html;
  return el.firstElementChild as HTMLElement;
}

function texts(root: Element, selector: string): string[] {
  return Array.from(root.querySelectorAll(selector)).map((el) => el.textContent);
}

describe('renderFileList', () => {
  function fullList(): string {
    return renderFileList({
      containerId: 'g-total',
      title: 'All Files',
      filenames: [FULL, BARE, 'lib/ghost.rb'],
      stats,
      allCoverage: { [FULL]: fullCoverage, [BARE]: bareCoverage },
      lineCoverage: true,
      branchCoverage: true,
      methodCoverage: true,
      primaryCoverage: 'line'
    });
  }

  test('renders headers, totals, and rows for every enabled criterion', () => {
    const container = parse(fullList());

    expect(container.id).toBe('g-total');
    expect(container.getAttribute('data-total-files')).toBe('3');
    expect(container.querySelector('.group_name')!.textContent).toBe('All Files');
    expect(container.querySelector('.covered_percent .yellow')!.textContent).toBe('80.00%');

    expect(texts(container, 'thead th .th-label')).toEqual(['File Name', 'Line Coverage', 'Branch Coverage', 'Method Coverage']);
    expect(Array.from(container.querySelectorAll('thead th')).map((th) => th.getAttribute('data-sort-key'))).toEqual([
      'file', 'line-percent', 'line-covered', 'line-total', 'branch-percent', 'branch-covered', 'branch-total',
      'method-percent', 'method-covered', 'method-total'
    ]);
    expect(texts(container, 'thead th.cell--numerator')).toEqual(['Covered', 'Covered', 'Covered']);
    expect(texts(container, 'thead th.cell--denominator')).toEqual(['Lines', 'Branches', 'Methods']);

    expect(container.querySelector('.t-file-count')!.textContent).toBe('3 files');
    expect(container.querySelector('.t-totals__line-num')!.textContent).toBe('8/');
    expect(container.querySelector('.t-totals__branch-den')!.textContent).toBe('4');
    expect(container.querySelector('.t-totals__method-pct')!.className).toContain('red');

    const rows = container.querySelectorAll('tbody tr.t-file');
    expect(rows).toHaveLength(2);

    const full = rows[0] as HTMLElement;
    expect(full.dataset.coveredLines).toBe('8');
    expect(full.dataset.relevantLines).toBe('10');
    expect(full.dataset.coveredBranches).toBe('3');
    expect(full.dataset.totalBranches).toBe('4');
    expect(full.dataset.coveredMethods).toBe('1');
    expect(full.dataset.totalMethods).toBe('2');
    expect(full.querySelector('.cell--line-pct')!.getAttribute('data-order')).toBe('80.00');
    expect(full.querySelector('.cell--branch-pct')!.getAttribute('data-order')).toBe('75.00');
    expect(full.querySelector('.cell--method-pct')!.getAttribute('data-order')).toBe('50.00');
    expect(texts(full, 'td.cell--numerator')).toEqual(['8/', '3/', '1/']);
    expect(texts(full, 'td.cell--denominator')).toEqual(['10', '4', '2']);
    const link = full.querySelector('a.src_link')!;
    expect(link.getAttribute('href')).toBe('#' + fileId(FULL));
    expect(link.getAttribute('title')).toBe(FULL);

    const bare = rows[1] as HTMLElement;
    expect(bare.dataset.coveredLines).toBe('0');
    expect(bare.dataset.totalMethods).toBe('0');
    expect(bare.querySelector('a.src_link')!.textContent).toBe(BARE);
    expect(bare.querySelector('.cell--line-pct')!.getAttribute('data-order')).toBe('100.00');
    expect(bare.querySelector('.cell--branch-pct')!.className).toContain('green');
    expect(bare.querySelector('.cell--method-pct')!.getAttribute('data-order')).toBe('100.00');
    expect(texts(bare, 'td.cell--numerator')).toEqual(['0/', '0/', '0/']);
    expect(texts(bare, 'td.cell--denominator')).toEqual(['0', '0', '0']);
  });

  test('emits well-formed markup with the cells and rows joined seamlessly', () => {
    const html = fullList();
    expect(html).toContain('</span><span class="covered_percent hide">');
    expect(html).toContain('</th></tr><tr class="totals-row">');
    expect(html).toContain(
      '<tbody><tr class="t-file" data-covered-lines="8" data-relevant-lines="10" data-covered-branches="3" ' +
      'data-total-branches="4" data-covered-methods="1" data-total-methods="2">'
    );
    expect(html).toContain('</a></td><td class="cell--coverage cell--line-pct');
    expect(html).toMatch(/<\/td><\/tr><\/tbody><\/table><\/div><\/div>$/);
  });

  test('uses the singular file label and renders only the enabled criterion', () => {
    const html = renderFileList({
      containerId: 'g-one',
      title: 'One',
      filenames: [FULL],
      stats: { lines: stats.lines },
      allCoverage: { [FULL]: fullCoverage },
      lineCoverage: true,
      branchCoverage: false,
      methodCoverage: false,
      primaryCoverage: 'line'
    });
    expect(html).toContain('1 file<');
    expect(html).not.toContain('Branch Coverage');
    expect(html).not.toContain('Method Coverage');
    expect(html).not.toContain('data-covered-branches');
    expect(html).not.toContain('data-covered-methods');
    expect(html).not.toContain('cell--branch-pct');
    expect(html).not.toContain('cell--method-pct');
  });

  test('leaves line coverage out entirely when it is disabled', () => {
    const html = renderFileList({
      containerId: 'g-branches',
      title: 'Branches',
      filenames: [FULL],
      stats: { branches: stats.branches },
      allCoverage: { [FULL]: fullCoverage },
      lineCoverage: false,
      branchCoverage: true,
      methodCoverage: false,
      primaryCoverage: 'branch'
    });
    expect(html).not.toContain('Line Coverage');
    expect(html).not.toContain('data-covered-lines');
    expect(html).not.toContain('cell--line-pct');
    expect(html).toContain('cell--branch-pct');
  });

  test('falls back to a 100% tab percentage when stats lack any criterion', () => {
    const container = parse(
      renderFileList({
        containerId: 'g-empty',
        title: 'Empty',
        filenames: [],
        stats: {},
        allCoverage: {},
        lineCoverage: false,
        branchCoverage: false,
        methodCoverage: false,
        primaryCoverage: 'line'
      })
    );
    expect(container.querySelector('.covered_percent .green')!.textContent).toBe('100.00%');
    expect(container.querySelector('.t-file-count')!.textContent).toBe('0 files');
    expect(container.querySelectorAll('tbody tr.t-file')).toHaveLength(0);
  });
});

describe('renderFileList with recorded contexts', () => {
  const trackedCoverage: FileCoverage = {
    source: ['a', 'b', 'c', 'd', 'e'],
    lines: [1, 1, 1, null, 1],
    lines_covered_percent: 100,
    covered_lines: 4,
    total_lines: 4,
    contexts: { '0': 'b' }
  };
  const untouchedCoverage: FileCoverage = {
    source: ['a', 'b'],
    lines: [1, 0],
    lines_covered_percent: 50,
    covered_lines: 1,
    total_lines: 2
  };

  function trackedList(contextsEnabled: boolean): HTMLElement {
    return parse(
      renderFileList({
        containerId: 'g-total',
        title: 'All Files',
        filenames: [FULL, BARE, 'lib/ghost.rb'],
        stats: {
          lines: { covered: 5, missed: 1, total: 6, percent: 83.33, strength: 1 }
        },
        allCoverage: { [FULL]: trackedCoverage, [BARE]: untouchedCoverage },
        lineCoverage: true,
        branchCoverage: false,
        methodCoverage: false,
        primaryCoverage: 'line',
        contextsEnabled
      })
    );
  }

  test('splits each line bar and carries the by-tests sort key', () => {
    const container = trackedList(true);
    expect(container.querySelectorAll('tbody tr.t-file')).toHaveLength(2);
    const row = container.querySelector('tbody tr.t-file')!;
    expect(row.getAttribute('data-covered-outside-lines')).toBe('2');
    const pctCell = row.querySelector('td.cell--line-pct')!;
    expect(pctCell.getAttribute('data-order')).toBe('100.00');
    expect(pctCell.getAttribute('data-order-2')).toBe('50.00');
    const fills = pctCell.querySelectorAll('.coverage-bar__fill');
    expect(fills.length).toBe(2);
    expect(fills[0].getAttribute('style')).toBe('width: 50.00%');
    expect(fills[1].getAttribute('style')).toBe('width: 50.00%');
    expect(fills[1].className).toContain('coverage-bar__fill--outside');
  });

  test('counts every covered line of an untouched file as outside', () => {
    const container = trackedList(true);
    const row = container.querySelectorAll('tbody tr.t-file')[1]!;
    expect(row.getAttribute('data-covered-outside-lines')).toBe('1');
    expect(row.querySelector('td.cell--line-pct')!.getAttribute('data-order-2')).toBe('0.00');
  });

  test('aggregates the outside share into the totals bar', () => {
    const container = trackedList(true);
    const totalsCell = container.querySelector('.t-totals__line-pct')!;
    const fills = totalsCell.querySelectorAll('.coverage-bar__fill');
    expect(fills.length).toBe(2);
    expect(fills[1].getAttribute('style')).toBe('width: 50.00%');
    expect(fills[0].getAttribute('style')).toBe('width: 33.33%');
  });

  test('renders exactly as before when the run recorded no contexts', () => {
    const container = trackedList(false);
    expect(container.querySelector('[data-covered-outside-lines]')).toBeNull();
    expect(container.querySelector('[data-order-2]')).toBeNull();
    expect(container.querySelector('.coverage-bar__fill--outside')).toBeNull();
  });
});

describe('renderFileList with production coverage', () => {
  function productionList(production?: ProductionData): HTMLElement {
    return parse(
      renderFileList({
        containerId: 'g-total',
        title: 'All Files',
        filenames: [FULL, BARE],
        stats: { lines: stats.lines },
        allCoverage: { [FULL]: fullCoverage, [BARE]: bareCoverage },
        lineCoverage: true,
        branchCoverage: false,
        methodCoverage: false,
        primaryCoverage: 'line',
        production
      })
    );
  }

  test('adds a sortable last-run column with an empty totals cell', () => {
    const container = productionList({
      files: { [FULL]: { lines: [1, 3], last_seen: '2026-08-20T12:00:00Z' } }
    });

    const header = container.querySelector('th.cell--production')!;
    expect(header.getAttribute('data-sort-key')).toBe('production');
    expect(header.textContent).toBe('Last Run in Production');
    expect(container.querySelector('.totals-row td.cell--production')!.textContent).toBe('');

    const cell = container.querySelector('tbody td.cell--production')!;
    expect(cell.getAttribute('data-order')).toBe(String(Date.parse('2026-08-20T12:00:00Z')));
    const abbr = cell.querySelector('abbr.timeago')!;
    expect(abbr.getAttribute('title')).toBe('2026-08-20T12:00:00Z');
    expect(abbr.textContent).toBe('2026-08-20');
  });

  test('marks a file the window never saw as never, sorted first ascending', () => {
    const container = productionList({ files: {} });
    const cell = container.querySelectorAll('tbody td.cell--production')[1]!;
    expect(cell.textContent).toBe('never');
    expect(cell.getAttribute('data-order')).toBe('-1');
    expect(cell.className).toContain('t-file__production--never');
  });

  test('marks a stamp-less or unparseable entry as ran, between never and any date', () => {
    const container = productionList({
      files: { [FULL]: { lines: [1] }, [BARE]: { lines: [2], last_seen: 'junk' } }
    });
    const cells = Array.from(container.querySelectorAll('tbody td.cell--production'));
    expect(cells).toHaveLength(2);
    for (const cell of cells) {
      expect(cell.textContent).toBe('ran');
      expect(cell.getAttribute('data-order')).toBe('0');
    }
  });

  test('renders exactly as before when the report carries no section', () => {
    const container = productionList(undefined);
    expect(container.querySelector('.cell--production')).toBeNull();
  });
});
