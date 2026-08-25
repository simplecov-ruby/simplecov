// File-list table markup: per-group container, column headers, totals row,
// and one row per source file, across the three coverage criteria — ported
// from the cucumber checks on the rendered group tables.
import { beforeAll, describe, expect, test } from 'bun:test';
import { fileId, precomputeFileIds } from '../src/format';
import { renderFileList } from '../src/render_list';
import type { FileCoverage, StatGroup } from '../src/types';

const FULL = 'lib/full.rb';
const BARE = 'lib/<bare>.rb'; // markup-significant name to prove escaping

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

// No percent or count fields at all, so every 100.0 / 0 fallback kicks in.
const bareCoverage: FileCoverage = { source: [] };

function parse(html: string): HTMLElement {
  const el = document.createElement('div');
  el.innerHTML = html;
  return el.firstElementChild as HTMLElement;
}

describe('renderFileList', () => {
  test('renders headers, totals, and rows for every enabled criterion', () => {
    const container = parse(
      renderFileList({
        containerId: 'g-total',
        title: 'All Files',
        filenames: [FULL, BARE, 'lib/ghost.rb'],
        stats,
        allCoverage: { [FULL]: fullCoverage, [BARE]: bareCoverage },
        lineCoverage: true,
        branchCoverage: true,
        methodCoverage: true,
        primaryCoverage: 'line'
      })
    );

    expect(container.id).toBe('g-total');
    expect(container.getAttribute('data-total-files')).toBe('3');
    expect(container.querySelector('.group_name')!.textContent).toBe('All Files');
    expect(container.querySelector('.covered_percent .yellow')!.textContent).toBe('80.00%');

    const headers = Array.from(container.querySelectorAll('thead th .th-label')).map(
      (el) => el.textContent
    );
    expect(headers).toEqual(['File Name', 'Line Coverage', 'Branch Coverage', 'Method Coverage']);
    expect(container.querySelector('thead th')!.getAttribute('data-sort-key')).toBe('file');

    expect(container.querySelector('.t-file-count')!.textContent).toBe('3 files');
    expect(container.querySelector('.t-totals__line-num')!.textContent).toBe('8/');
    expect(container.querySelector('.t-totals__branch-den')!.textContent).toBe('4');
    expect(container.querySelector('.t-totals__method-pct')!.className).toContain('red');

    // ghost.rb is listed in the group but has no coverage entry, so no row
    const rows = container.querySelectorAll('tbody tr.t-file');
    expect(rows).toHaveLength(2);

    const full = rows[0] as HTMLElement;
    expect(full.dataset.coveredLines).toBe('8');
    expect(full.dataset.relevantLines).toBe('10');
    expect(full.dataset.coveredBranches).toBe('3');
    expect(full.dataset.totalBranches).toBe('4');
    expect(full.dataset.coveredMethods).toBe('1');
    expect(full.dataset.totalMethods).toBe('2');
    const link = full.querySelector('a.src_link')!;
    expect(link.getAttribute('href')).toBe('#' + fileId(FULL));
    expect(link.getAttribute('title')).toBe(FULL);

    // the fieldless file falls back to 100% / 0 counts and escapes its name
    const bare = rows[1] as HTMLElement;
    expect(bare.dataset.coveredLines).toBe('0');
    expect(bare.dataset.totalMethods).toBe('0');
    expect(bare.querySelector('a.src_link')!.textContent).toBe(BARE);
    expect(bare.querySelector('.cell--line-pct')!.getAttribute('data-order')).toBe('100.00');
    expect(bare.querySelector('.cell--branch-pct')!.className).toContain('green');
    expect(bare.querySelector('.cell--method-pct')!.getAttribute('data-order')).toBe('100.00');
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
  // 0xb = bits 0,1,3 -> lines 1, 2, 4 executed by the one context. Line 4
  // is non-executable, so of the covered lines (1, 2, 3, 5) two are covered
  // outside tests: 50% of the file's 4 relevant lines is by tests.
  const trackedCoverage: FileCoverage = {
    source: ['a', 'b', 'c', 'd', 'e'],
    lines: [1, 1, 1, null, 1],
    lines_covered_percent: 100,
    covered_lines: 4,
    total_lines: 4,
    contexts: { '0': 'b' }
  };
  // No `contexts` table: an untouched file, all its covered lines outside.
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
        filenames: [FULL, BARE],
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
    // 3 of 6 relevant lines outside tests: 50% grey, 33.33% by tests.
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
