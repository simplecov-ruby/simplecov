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
