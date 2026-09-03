import { describe, expect, test } from 'bun:test';
import {
  renderCoverageBar,
  renderCoverageCells,
  renderCoverageSummary,
  renderHeaderCells
} from '../src/render_cells';

describe('renderCoverageBar', () => {
  test('sizes and colours the fill by the coverage band', () => {
    expect(renderCoverageBar(95.5)).toBe(
      '<div class="bar-sizer"><div class="coverage-bar">' +
        '<div class="coverage-bar__fill coverage-bar__fill--green" style="width: 95.50%"></div>' +
        '</div></div>'
    );
    expect(renderCoverageBar(80)).toContain('coverage-bar__fill--yellow');
    expect(renderCoverageBar(10)).toContain('coverage-bar__fill--red');
  });
});

describe('renderCoverageCells', () => {
  test('totals cells carry the t-totals__ hooks the live updater targets', () => {
    const html = renderCoverageCells(80, 4, 5, 'line', true);
    expect(html).toContain('t-totals__line-pct yellow');
    expect(html).toContain('t-totals__line-num">4/');
    expect(html).toContain('t-totals__line-den">5');
    expect(html).not.toContain('data-order');
  });

  test('file-row cells expose data-order for the sorter and group digits', () => {
    const html = renderCoverageCells(100, 1250, 1250, 'branch', false);
    expect(html).toContain('cell--branch-pct green" data-order="100.00">');
    expect(html).toContain('cell--numerator" data-order="1250">1,250/');
    expect(html).toContain('cell--denominator" data-order="1250">1,250');
  });
});

describe('renderHeaderCells', () => {
  test('renders the label, filter controls, and count headers', () => {
    const html = renderHeaderCells('Line Coverage', 'line', 'Covered', 'Lines');
    expect(html).toContain('<span class="th-label">Line Coverage</span>');
    expect(html).toContain('col-filter__op" data-type="line"');
    expect(html).toContain('col-filter__value" min="0" max="100" data-type="line"');
    expect(html).toContain('data-sort-key="line-percent"');
    expect(html).toContain('cell--numerator" data-sort-key="line-covered">Covered');
    expect(html).toContain('cell--denominator" data-sort-key="line-total">Lines');
  });
});

describe('renderCoverageSummary', () => {
  const base = {
    coveredLines: 8,
    totalLines: 10,
    coveredBranches: 3,
    totalBranches: 4,
    coveredMethods: 1,
    totalMethods: 2,
    lineCoverage: true,
    branchCoverage: true,
    methodCoverage: true,
    showMethodToggle: true
  };

  function summaryOf(html: string, type: string): string {
    const el = document.createElement('div');
    el.innerHTML = html;
    return el.querySelector(`.t-${type}-summary`)!.innerHTML;
  }

  test('renders each enabled criterion with its percent and missed count', () => {
    const html = renderCoverageSummary(base);
    expect(summaryOf(html, 'line')).toContain('Line coverage: <span class="yellow"><b>80.00%</b></span>');
    expect(summaryOf(html, 'line')).toContain('8/10 relevant lines covered');
    expect(summaryOf(html, 'line')).toContain('<span class="red"><b>2</b> missed</span>');
    expect(summaryOf(html, 'branch')).toContain('Branch coverage: <span class="yellow"><b>75.00%</b></span>');
    expect(summaryOf(html, 'branch')).toContain('3/4 covered');
    expect(summaryOf(html, 'branch')).toContain('<span class="missed-branch-text"><b>1</b> missed</span>');
    expect(summaryOf(html, 'method')).toContain('Method coverage: <span class="red"><b>50.00%</b></span>');
    expect(summaryOf(html, 'method')).toContain('t-missed-method-toggle');
  });

  test('marks disabled criteria instead of showing numbers', () => {
    const html = renderCoverageSummary({
      ...base,
      lineCoverage: false,
      branchCoverage: false,
      methodCoverage: false
    });
    expect(html.match(/coverage-disabled/g)).toHaveLength(3);
    expect(summaryOf(html, 'branch')).toContain('Branch coverage: <span class="coverage-disabled">disabled</span>');
  });

  test('omits the missed span at full coverage and treats an empty criterion as 100%', () => {
    const html = renderCoverageSummary({
      ...base,
      coveredLines: 10,
      totalLines: 10,
      coveredBranches: 0,
      totalBranches: 0,
      coveredMethods: 2,
      totalMethods: 2
    });
    expect(html).not.toContain('missed');
    expect(summaryOf(html, 'line')).toContain('<span class="green"><b>100.00%</b></span>');
    expect(summaryOf(html, 'branch')).toContain('<span class="green"><b>100.00%</b></span>');
    expect(summaryOf(html, 'branch')).toContain('0/0 covered');
  });

  test('renders missed methods as plain text when the toggle is hidden', () => {
    const html = renderCoverageSummary({ ...base, showMethodToggle: false });
    expect(html).toContain('<span class="missed-method-text-color"><b>1</b> missed</span>');
    expect(html).not.toContain('t-missed-method-toggle');
  });

  test('splits a tracked line summary into by-tests and outside-tests shares', () => {
    const html = renderCoverageSummary({ ...base, coveredByTests: 6, coveredOutsideTests: 2 });
    expect(summaryOf(html, 'line')).toBe(
      '\n    Line coverage: <span class="yellow"><b>80.00%</b></span>' +
      '<span class="coverage-cell__fraction"> 6/10 relevant lines covered by tests</span>' +
      '<span class="coverage-cell__fraction">,</span>\n    ' +
      '<span class="coverage-cell__fraction outside-tests-text">2/10 relevant lines covered outside tests</span>' +
      '<span class="coverage-cell__fraction">,</span>\n    ' +
      '<span class="red"><b>2</b> missed</span>\n  '
    );
  });

  test('a tracked summary omits the outside and missed parts when they are zero', () => {
    const html = renderCoverageSummary({ ...base, coveredLines: 10, coveredByTests: 10 });
    expect(summaryOf(html, 'line')).toBe(
      '\n    Line coverage: <span class="green"><b>100.00%</b></span>' +
      '<span class="coverage-cell__fraction"> 10/10 relevant lines covered by tests</span>\n  '
    );
  });

  test('a tracked summary treats an empty file set as 100%', () => {
    const html = renderCoverageSummary({ ...base, coveredLines: 0, totalLines: 0, coveredByTests: 0 });
    expect(summaryOf(html, 'line')).toContain('<span class="green"><b>100.00%</b></span>');
    expect(summaryOf(html, 'line')).toContain('0/0 relevant lines covered by tests');
  });

  test('a tracked summary falls back to the plain one when line coverage is off', () => {
    const html = renderCoverageSummary({ ...base, lineCoverage: false, coveredByTests: 6 });
    expect(summaryOf(html, 'line')).toContain('coverage-disabled');
  });
});

describe('renderCoverageBar with recorded contexts', () => {
  test('splits the fill into by-tests and outside-tests segments', () => {
    expect(renderCoverageBar(100, 10)).toBe(
      '<div class="bar-sizer"><div class="coverage-bar">' +
        '<div class="coverage-bar__fill coverage-bar__fill--green coverage-bar__fill--split" style="width: 90.00%"></div>' +
        '<div class="coverage-bar__fill coverage-bar__fill--outside" style="width: 10.00%"></div>' +
        '</div></div>'
    );
  });

  test('bands the by-tests segment by the overall percent', () => {
    const html = renderCoverageBar(80, 30);
    expect(html).toContain('coverage-bar__fill--yellow coverage-bar__fill--split" style="width: 50.00%"');
    expect(html).toContain('coverage-bar__fill--outside" style="width: 30.00%"');
  });

  test('keeps the single fill when nothing was covered outside tests', () => {
    expect(renderCoverageBar(100, 0)).toBe(renderCoverageBar(100));
  });
});

describe('renderCoverageCells with recorded contexts', () => {
  test('file-row cells sort primarily by percent, secondarily by-tests', () => {
    const html = renderCoverageCells(100, 10, 10, 'line', false, 2);
    expect(html).toContain('data-order="100.00" data-order-2="80.00"');
    expect(html).toContain('coverage-bar__fill--green coverage-bar__fill--split" style="width: 80.00%"');
    expect(html).toContain('coverage-bar__fill--outside" style="width: 20.00%"');
  });

  test('totals cells split the bar but stay non-sortable', () => {
    const html = renderCoverageCells(100, 10, 10, 'line', true, 2);
    expect(html).toContain('coverage-bar__fill--outside');
    expect(html).not.toContain('data-order');
  });

  test('a fully test-covered file keeps the single fill and a 100 tiebreak', () => {
    const html = renderCoverageCells(100, 10, 10, 'line', false, 0);
    expect(html).toContain('data-order="100.00" data-order-2="100.00"');
    expect(html).not.toContain('coverage-bar__fill--outside');
    expect(html).not.toContain('coverage-bar__fill--split');
  });

  test('a file without relevant lines gets no tiebreak', () => {
    const html = renderCoverageCells(100, 0, 0, 'line', false, 0);
    expect(html).toContain('data-order="100.00">');
    expect(html).not.toContain('data-order-2');
    expect(html).not.toContain('NaN');
  });

  test('an untracked run renders exactly as before', () => {
    const html = renderCoverageCells(100, 10, 10, 'line', false);
    expect(html).toContain('data-order="100.00">');
    expect(html).not.toContain('data-order-2');
    expect(html).not.toContain('coverage-bar__fill--outside');
  });
});
