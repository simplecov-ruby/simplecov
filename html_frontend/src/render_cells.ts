// Reusable coverage-cell and summary HTML builders shared by the file-list
// table, the per-file source view, and the live totals updater.

import { pctClass, fmtNum, fmtPct } from './format';

// Under `track_tests`, `outsidePct` splits the fill: the band-coloured
// share covered by recorded tests, then a slate share covered only outside
// them, so the bar mirrors the source view's drained lines. The band stays
// a function of the overall percent — the split changes what the fill is
// made of, not which band the file is in.
export function renderCoverageBar(pct: number, outsidePct?: number): string {
  const css = pctClass(pct);
  if (!outsidePct) {
    return `<div class="bar-sizer"><div class="coverage-bar"><div class="coverage-bar__fill coverage-bar__fill--${css}" style="width: ${fmtPct(pct)}%"></div></div></div>`;
  }
  return '<div class="bar-sizer"><div class="coverage-bar">' +
    `<div class="coverage-bar__fill coverage-bar__fill--${css} coverage-bar__fill--split" style="width: ${fmtPct(pct - outsidePct)}%"></div>` +
    `<div class="coverage-bar__fill coverage-bar__fill--outside" style="width: ${fmtPct(outsidePct)}%"></div>` +
    '</div></div>';
}

export function renderCoverageCells(pct: number, covered: number, total: number, type: string, totals: boolean, outside?: number): string {
  const css = pctClass(pct);
  const pctStr = fmtPct(pct);
  const outsidePct = outside === undefined || total === 0 ? undefined : (outside * 100.0) / total;
  const barAndPct = `<div class="coverage-cell">${renderCoverageBar(pct, outsidePct)}<span class="coverage-pct">${pctStr}%</span></div>`;

  if (totals) {
    return `<td class="cell--coverage strong t-totals__${type}-pct ${css}">${barAndPct}</td>` +
           `<td class="cell--numerator strong t-totals__${type}-num">${fmtNum(covered)}/</td>` +
           `<td class="cell--denominator strong t-totals__${type}-den">${fmtNum(total)}</td>`;
  }
  // Every sortable cell carries data-order: the displayed counts are
  // comma-grouped, and the sorter's Number.parseFloat would stop at the
  // first separator and rank "1,250" below "999". Tracked runs add the
  // by-tests percent as data-order-2, the sorter's tie-breaker, so equal
  // coverage ranks by how much of it recorded tests produced.
  const tiebreak = outsidePct === undefined ? '' : ` data-order-2="${fmtPct(pct - outsidePct)}"`;
  const order = ` data-order="${fmtPct(pct)}"${tiebreak}`;
  return `<td class="cell--coverage cell--${type}-pct ${css}"${order}>${barAndPct}</td>` +
         `<td class="cell--numerator" data-order="${covered}">${fmtNum(covered)}/</td>` +
         `<td class="cell--denominator" data-order="${total}">${fmtNum(total)}</td>`;
}

export function renderHeaderCells(label: string, type: string, coveredLabel: string, totalLabel: string): string {
  return `<th class="cell--coverage" data-sort-key="${type}-percent">
      <div class="th-with-filter">
        <span class="th-label">${label}</span>
        <div class="col-filter__coverage">
          <select class="col-filter__op" data-type="${type}"><option value="lt">&lt;</option><option value="lte" selected>&le;</option><option value="eq">=</option><option value="gte">&ge;</option><option value="gt">&gt;</option></select>
          <span class="col-filter__pct-wrap"><input type="number" class="col-filter__value" min="0" max="100" data-type="${type}" value="100" step="any"></span>
        </div>
      </div>
    </th>
    <th class="cell--numerator" data-sort-key="${type}-covered">${coveredLabel}</th>
    <th class="cell--denominator" data-sort-key="${type}-total">${totalLabel}</th>`;
}

interface TypeSummary {
  type: string;
  label: string;
  covered: number;
  total: number;
  enabled: boolean;
  suffix?: string;
  missedClass?: string;
  toggle?: boolean;
}

function renderTypeSummary(summary: TypeSummary): string {
  const { type, label, covered, total, enabled, toggle } = summary;
  if (!enabled) {
    return `<div class="t-${type}-summary">\n    ${label}: <span class="coverage-disabled">disabled</span>\n  </div>`;
  }
  const missed = total - covered;
  const pct = total > 0 ? (covered * 100.0 / total) : 100.0;
  const css = pctClass(pct);
  const suffix = summary.suffix || 'covered';
  const missedClass = summary.missedClass || 'red';

  let parts = `<div class="t-${type}-summary">\n    ${label}: ` +
    `<span class="${css}"><b>${fmtPct(pct)}%</b></span>` +
    `<span class="coverage-cell__fraction"> ${covered}/${total} ${suffix}</span>`;

  if (missed > 0) {
    const missedHtml = toggle
      ? `<a href="#" class="t-missed-method-toggle"><b>${missed}</b> missed</a>`
      : `<span class="${missedClass}"><b>${missed}</b> missed</span>`;
    parts += `<span class="coverage-cell__fraction">,</span>\n    ${missedHtml}`;
  }
  parts += '\n  </div>';
  return parts;
}

// The line summary of a tracked report: the percent is still the file's
// line coverage, but the fraction attributes it — how many relevant lines
// recorded tests covered, then how many were covered only outside them,
// then the missed remainder the untracked row would also report.
function renderTrackedLineSummary(covered: number, total: number, byTests: number, outside: number): string {
  const pct = total > 0 ? (covered * 100.0 / total) : 100.0;
  const missed = total - covered;

  let parts = '<div class="t-line-summary">\n    Line coverage: ' +
    `<span class="${pctClass(pct)}"><b>${fmtPct(pct)}%</b></span>` +
    `<span class="coverage-cell__fraction"> ${byTests}/${total} relevant lines covered by tests</span>`;

  if (outside > 0) {
    parts += '<span class="coverage-cell__fraction">,</span>\n    ' +
      `<span class="coverage-cell__fraction outside-tests-text">${outside}/${total} relevant lines covered outside tests</span>`;
  }
  if (missed > 0) {
    parts += '<span class="coverage-cell__fraction">,</span>\n    ' +
      `<span class="red"><b>${missed}</b> missed</span>`;
  }
  return parts + '\n  </div>';
}

interface CoverageSummaryArgs {
  coveredLines: number;
  totalLines: number;
  coveredBranches: number;
  totalBranches: number;
  coveredMethods: number;
  totalMethods: number;
  lineCoverage: boolean;
  branchCoverage: boolean;
  methodCoverage: boolean;
  showMethodToggle: boolean;
  // Present only when the report carries recorded contexts: the relevant
  // covered lines some recorded test executed, and the remainder covered
  // outside them (see render_source.ts). The line row then splits its
  // fraction by that attribution instead of stating one covered count.
  coveredByTests?: number;
  coveredOutsideTests?: number;
}

export function renderCoverageSummary(args: CoverageSummaryArgs): string {
  const lineSummary = args.coveredByTests === undefined || !args.lineCoverage
    ? renderTypeSummary({ type: 'line', label: 'Line coverage', covered: args.coveredLines, total: args.totalLines, enabled: args.lineCoverage, suffix: 'relevant lines covered' })
    : renderTrackedLineSummary(args.coveredLines, args.totalLines, args.coveredByTests, args.coveredOutsideTests || 0);
  return '<div class="summary-stats">' +
    lineSummary +
    renderTypeSummary({ type: 'branch', label: 'Branch coverage', covered: args.coveredBranches, total: args.totalBranches, enabled: args.branchCoverage, missedClass: 'missed-branch-text' }) +
    renderTypeSummary({ type: 'method', label: 'Method coverage', covered: args.coveredMethods, total: args.totalMethods, enabled: args.methodCoverage, missedClass: 'missed-method-text-color', toggle: args.showMethodToggle }) +
    '</div>';
}
