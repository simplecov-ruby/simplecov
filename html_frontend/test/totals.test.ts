// The live totals row: recomputing per-group counts and coverage cells as
// rows are hidden and shown by the filters — ported from the cucumber
// filtering scenarios that watched the totals row change.
import { describe, expect, test } from 'bun:test';
import { updateTotalsRow } from '../src/totals';

interface ContainerOptions {
  totalFiles: number;
  fileCountCell?: boolean;
  criteria?: string[];
  rows: string[];
}

// A pared-down file-list container: a totals row with the t-totals__ cells
// the updater rewrites, and whatever file rows a scenario needs.
function buildContainer(options: ContainerOptions): HTMLElement {
  const criteria = options.criteria ?? ['line'];
  const totalsCells = criteria
    .map(
      (type) =>
        `<td class="t-totals__${type}-pct stale">stale</td>` +
        `<td class="t-totals__${type}-num">stale</td>` +
        `<td class="t-totals__${type}-den">stale</td>`
    )
    .join('');
  const container = document.createElement('div');
  container.className = 'file_list_container';
  container.setAttribute('data-total-files', String(options.totalFiles));
  container.innerHTML =
    '<table class="file_list"><thead><tr class="totals-row">' +
    (options.fileCountCell === false ? '' : '<td class="strong t-file-count"></td>') +
    totalsCells +
    '</tr></thead><tbody>' +
    options.rows.join('') +
    '</tbody></table>';
  return container;
}

function row(attrs: string, hidden = false): string {
  return `<tr class="t-file" ${attrs}${hidden ? ' style="display: none"' : ''}><td>x</td></tr>`;
}

describe('updateTotalsRow', () => {
  test('sums visible rows and shows the plain count when nothing is filtered', () => {
    const container = buildContainer({
      totalFiles: 3,
      rows: [
        row('data-covered-lines="8" data-relevant-lines="10"'),
        row('data-covered-lines="2" data-relevant-lines="2"'),
        row('') // no data attributes: counts as 0/0
      ]
    });
    updateTotalsRow(container);

    expect(container.querySelector('.t-file-count')!.textContent).toBe('3 files');
    const pct = container.querySelector('.t-totals__line-pct')!;
    expect(pct.className).toContain('yellow');
    expect(pct.innerHTML).toContain('83.33%');
    expect(pct.innerHTML).toContain('coverage-bar__fill--yellow');
    expect(container.querySelector('.t-totals__line-num')!.textContent).toBe('10/');
    expect(container.querySelector('.t-totals__line-den')!.textContent).toBe('12');
  });

  test('shows filtered/total counts and excludes hidden rows from the sums', () => {
    const container = buildContainer({
      totalFiles: 3,
      criteria: ['line', 'branch', 'method'],
      rows: [
        row(
          'data-covered-lines="4" data-relevant-lines="4" ' +
            'data-covered-branches="1" data-total-branches="2" ' +
            'data-covered-methods="1" data-total-methods="1"'
        ),
        row(
          'data-covered-lines="0" data-relevant-lines="4" ' +
            'data-covered-branches="0" data-total-branches="2" ' +
            'data-covered-methods="0" data-total-methods="1"'
        ),
        row('data-covered-lines="0" data-relevant-lines="100"', true)
      ]
    });
    updateTotalsRow(container);

    expect(container.querySelector('.t-file-count')!.textContent).toBe('2/3 files');
    expect(container.querySelector('.t-totals__line-num')!.textContent).toBe('4/');
    expect(container.querySelector('.t-totals__line-den')!.textContent).toBe('8');
    expect(container.querySelector('.t-totals__line-pct')!.className).toContain('red');
    expect(container.querySelector('.t-totals__branch-pct')!.innerHTML).toContain('25.00%');
    const methodPct = container.querySelector('.t-totals__method-pct')!;
    expect(methodPct.className).toContain('red');
    expect(methodPct.innerHTML).toContain('50.00%');
  });

  test('uses the singular label when one row remains', () => {
    const container = buildContainer({
      totalFiles: 2,
      rows: [
        row('data-covered-lines="1" data-relevant-lines="1"'),
        row('data-covered-lines="1" data-relevant-lines="1"', true)
      ]
    });
    updateTotalsRow(container);
    expect(container.querySelector('.t-file-count')!.textContent).toBe('1/2 file');
  });

  test('clears the coverage cells when no relevant lines remain', () => {
    const container = buildContainer({
      totalFiles: 1,
      rows: [row('data-covered-lines="0" data-relevant-lines="0"')]
    });
    const pct = container.querySelector('.t-totals__line-pct')!;
    pct.classList.add('green');
    updateTotalsRow(container);

    expect(pct.innerHTML).toBe('');
    expect(pct.classList.contains('green')).toBe(false);
    expect(container.querySelector('.t-totals__line-num')!.textContent).toBe('');
    expect(container.querySelector('.t-totals__line-den')!.textContent).toBe('');
  });

  test('tolerates a container without a file-count cell', () => {
    const container = buildContainer({
      totalFiles: 1,
      fileCountCell: false,
      rows: [row('data-covered-lines="1" data-relevant-lines="1"')]
    });
    updateTotalsRow(container);
    expect(container.querySelector('.t-totals__line-pct')!.innerHTML).toContain('100.00%');
  });
});
