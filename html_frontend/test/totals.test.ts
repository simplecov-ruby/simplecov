import { describe, expect, test } from 'bun:test';
import { updateTotalsRow } from '../src/totals';

interface ContainerOptions {
  totalFiles: number;
  fileCountCell?: boolean;
  criteria?: string[];
  rows: string[];
}

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

function fillWidths(cell: Element): string[] {
  return Array.from(cell.querySelectorAll('.coverage-bar__fill')).map((fill) => fill.getAttribute('style')!);
}

describe('updateTotalsRow', () => {
  test('sums visible rows and shows the plain count when nothing is filtered', () => {
    const container = buildContainer({
      totalFiles: 3,
      rows: [
        row('data-covered-lines="8" data-relevant-lines="10"'),
        row('data-covered-lines="2" data-relevant-lines="2"'),
        row('')
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

  test('replaces a stale band class with the recomputed one', () => {
    const container = buildContainer({
      totalFiles: 1,
      rows: [row('data-covered-lines="8" data-relevant-lines="10"')]
    });
    const pct = container.querySelector('.t-totals__line-pct')!;
    pct.classList.add('green', 'yellow', 'red');
    updateTotalsRow(container);

    expect(pct.classList.contains('green')).toBe(false);
    expect(pct.classList.contains('red')).toBe(false);
    expect(pct.classList.contains('yellow')).toBe(true);

    container.querySelector('tbody')!.innerHTML = row('data-covered-lines="10" data-relevant-lines="10"');
    updateTotalsRow(container);
    expect(pct.classList.contains('yellow')).toBe(false);
    expect(pct.classList.contains('green')).toBe(true);
  });

  test('clears the coverage cells when no relevant lines remain', () => {
    const container = buildContainer({
      totalFiles: 1,
      rows: [row('data-covered-lines="0" data-relevant-lines="0"')]
    });
    const pct = container.querySelector('.t-totals__line-pct')!;
    pct.classList.add('green', 'yellow', 'red');
    updateTotalsRow(container);

    expect(pct.innerHTML).toBe('');
    expect(pct.classList.contains('green')).toBe(false);
    expect(pct.classList.contains('yellow')).toBe(false);
    expect(pct.classList.contains('red')).toBe(false);
    expect(container.querySelector('.t-totals__line-num')!.textContent).toBe('');
    expect(container.querySelector('.t-totals__line-den')!.textContent).toBe('');
  });

  test('updates whichever totals cells a row has', () => {
    const container = document.createElement('div');
    container.setAttribute('data-total-files', '2');
    container.innerHTML =
      '<table><thead><tr class="totals-row"><td class="t-totals__line-pct"></td>' +
      '<td class="t-totals__branch-num"></td><td class="t-totals__branch-den"></td></tr></thead><tbody>' +
      row('data-covered-lines="1" data-relevant-lines="2" data-covered-branches="1" data-total-branches="4"') +
      row('data-covered-lines="0" data-relevant-lines="0" data-covered-branches="0" data-total-branches="0"') +
      '</tbody></table>';
    updateTotalsRow(container);
    expect(container.querySelector('.t-totals__line-pct')!.innerHTML).toContain('50.00%');
    expect(container.querySelector('.t-totals__branch-num')!.textContent).toBe('1/');
    expect(container.querySelector('.t-totals__branch-den')!.textContent).toBe('4');

    container.querySelector('tbody')!.innerHTML = row('data-covered-lines="0" data-relevant-lines="0"');
    updateTotalsRow(container);
    expect(container.querySelector('.t-totals__line-pct')!.innerHTML).toBe('');
    expect(container.querySelector('.t-totals__branch-num')!.textContent).toBe('');
    expect(container.querySelector('.t-totals__branch-den')!.textContent).toBe('');
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

describe('updateTotalsRow with recorded contexts', () => {
  test('keeps the outside-tests share in the recomputed line bar', () => {
    const container = buildContainer({
      totalFiles: 2,
      rows: [
        row('data-covered-lines="4" data-relevant-lines="4" data-covered-outside-lines="1"'),
        row('data-covered-lines="4" data-relevant-lines="4" data-covered-outside-lines="3"', true)
      ]
    });
    updateTotalsRow(container);
    expect(fillWidths(container.querySelector('.t-totals__line-pct')!)).toEqual(['width: 75.00%', 'width: 25.00%']);
  });

  test('sums the outside share across tracked and untracked rows', () => {
    const container = buildContainer({
      totalFiles: 2,
      criteria: ['line', 'branch'],
      rows: [
        row('data-covered-lines="4" data-relevant-lines="4" data-covered-outside-lines="1" data-covered-branches="2" data-total-branches="2"'),
        row('data-covered-lines="4" data-relevant-lines="4" data-covered-branches="2" data-total-branches="2"')
      ]
    });
    updateTotalsRow(container);
    expect(fillWidths(container.querySelector('.t-totals__line-pct')!)).toEqual(['width: 87.50%', 'width: 12.50%']);
    expect(fillWidths(container.querySelector('.t-totals__branch-pct')!)).toEqual(['width: 100.00%']);
  });

  test('leaves untracked line bars whole', () => {
    const container = buildContainer({
      totalFiles: 1,
      rows: [row('data-covered-lines="4" data-relevant-lines="4"')]
    });
    updateTotalsRow(container);
    expect(fillWidths(container.querySelector('.t-totals__line-pct')!)).toEqual(['width: 100.00%']);
  });
});
