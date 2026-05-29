// Reusable coverage-cell and summary HTML builders shared by the file-list
// table, the per-file source view, and the live totals updater.

import { pctClass, fmtNum, fmtPct } from './format';

export function renderCoverageBar(pct: number): string {
  const css = pctClass(pct);
  const width = fmtPct(pct);
  return `<div class="bar-sizer"><div class="coverage-bar"><div class="coverage-bar__fill coverage-bar__fill--${css}" style="width: ${width}%"></div></div></div>`;
}

export function renderCoverageCells(pct: number, covered: number, total: number, type: string, totals: boolean): string {
  const css = pctClass(pct);
  const pctStr = fmtPct(pct);
  const barAndPct = `<div class="coverage-cell">${renderCoverageBar(pct)}<span class="coverage-pct">${pctStr}%</span></div>`;

  if (totals) {
    return `<td class="cell--coverage strong t-totals__${type}-pct ${css}">${barAndPct}</td>` +
           `<td class="cell--numerator strong t-totals__${type}-num">${fmtNum(covered)}/</td>` +
           `<td class="cell--denominator strong t-totals__${type}-den">${fmtNum(total)}</td>`;
  }
  const order = ` data-order="${fmtPct(pct)}"`;
  return `<td class="cell--coverage cell--${type}-pct ${css}"${order}>${barAndPct}</td>` +
         `<td class="cell--numerator">${fmtNum(covered)}/</td>` +
         `<td class="cell--denominator">${fmtNum(total)}</td>`;
}

export function renderHeaderCells(label: string, type: string, coveredLabel: string, totalLabel: string): string {
  return `<th class="cell--coverage">
      <div class="th-with-filter">
        <span class="th-label">${label}</span>
        <div class="col-filter__coverage">
          <select class="col-filter__op" data-type="${type}"><option value="lt">&lt;</option><option value="lte" selected>&le;</option><option value="eq">=</option><option value="gte">&ge;</option><option value="gt">&gt;</option></select>
          <span class="col-filter__pct-wrap"><input type="number" class="col-filter__value" min="0" max="100" data-type="${type}" value="100" step="any"></span>
        </div>
      </div>
    </th>
    <th class="cell--numerator">${coveredLabel}</th>
    <th class="cell--denominator">${totalLabel}</th>`;
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

interface CoverageSummaryArgs {
  coveredLines: number;
  totalLines: number;
  coveredBranches: number;
  totalBranches: number;
  coveredMethods: number;
  totalMethods: number;
  branchCoverage: boolean;
  methodCoverage: boolean;
  showMethodToggle: boolean;
}

export function renderCoverageSummary(args: CoverageSummaryArgs): string {
  return '<div class="summary-stats">' +
    renderTypeSummary({ type: 'line', label: 'Line coverage', covered: args.coveredLines, total: args.totalLines, enabled: true, suffix: 'relevant lines covered' }) +
    renderTypeSummary({ type: 'branch', label: 'Branch coverage', covered: args.coveredBranches, total: args.totalBranches, enabled: args.branchCoverage, missedClass: 'missed-branch-text' }) +
    renderTypeSummary({ type: 'method', label: 'Method coverage', covered: args.coveredMethods, total: args.totalMethods, enabled: args.methodCoverage, missedClass: 'missed-method-text-color', toggle: args.showMethodToggle }) +
    '</div>';
}
