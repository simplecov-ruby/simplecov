// The per-group totals row: the data-attribute map shared with filtering, and
// the live recomputation of totals as rows are shown or hidden.

import { $, $$ } from './dom';
import { pctClass, fmtNum, fmtPct } from './format';
import { renderCoverageBar } from './render_cells';

export interface DataAttrPair {
  covered: string;
  total: string;
}

export const dataAttrMap: Record<string, DataAttrPair> = {
  line:   { covered: 'coveredLines',   total: 'relevantLines' },
  branch: { covered: 'coveredBranches', total: 'totalBranches' },
  method: { covered: 'coveredMethods',  total: 'totalMethods' }
};

export function updateTotalsRow(container: Element): void {
  const rows = $$('tbody tr.t-file', container)
    .filter(r => (r as HTMLElement).style.display !== 'none');

  function sumData(attr: string): number {
    return rows.reduce(
      (total, r) => total + (Number.parseInt((r as HTMLElement).dataset[attr] || '0', 10) || 0),
      0
    );
  }

  const fileCount = $('.t-file-count', container);
  const totalFiles = Number.parseInt(container.getAttribute('data-total-files') || '0', 10);
  if (fileCount) {
    const label = rows.length === 1 ? ' file' : ' files';
    fileCount.textContent = rows.length === totalFiles
      ? fmtNum(totalFiles) + label
      : fmtNum(rows.length) + '/' + fmtNum(totalFiles) + label;
  }

  for (const type of Object.keys(dataAttrMap)) {
    const attrs = dataAttrMap[type];
    const prefix = `.t-totals__${type}`;
    if (!$(prefix + '-pct', container)) continue;
    updateCoverageCells(container, prefix, sumData(attrs.covered), sumData(attrs.total));
  }
}

function updateCoverageCells(
  container: Element,
  prefix: string,
  covered: number,
  total: number
): void {
  const covCell = $(prefix + '-pct', container);
  const numEl = $(prefix + '-num', container);
  const denEl = $(prefix + '-den', container);
  if (total === 0) {
    if (covCell) {
      covCell.innerHTML = '';
      covCell.classList.remove('green', 'yellow', 'red');
    }
    if (numEl) numEl.textContent = '';
    if (denEl) denEl.textContent = '';
    return;
  }
  const p = (covered * 100.0) / total;
  const cls = pctClass(p);
  if (covCell) {
    covCell.innerHTML = `<div class="coverage-cell">${renderCoverageBar(p)}<span class="coverage-pct">${fmtPct(p)}%</span></div>`;
    covCell.classList.remove('green', 'yellow', 'red');
    covCell.classList.add(cls);
  }
  if (numEl) numEl.textContent = fmtNum(covered) + '/';
  if (denEl) denEl.textContent = fmtNum(total);
}
