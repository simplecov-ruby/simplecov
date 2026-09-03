
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
    return rows.reduce((total, r) => total + (Number((r as HTMLElement).dataset[attr]) || 0), 0);
  }

  const fileCount = $('.t-file-count', container);
  const totalFiles = Number(container.getAttribute('data-total-files'));
  if (fileCount) {
    const label = rows.length === 1 ? ' file' : ' files';
    fileCount.textContent = rows.length === totalFiles
      ? fmtNum(totalFiles) + label
      : fmtNum(rows.length) + '/' + fmtNum(totalFiles) + label;
  }

  for (const type of Object.keys(dataAttrMap)) {
    const attrs = dataAttrMap[type];
    const outside = type === 'line' ? sumData('coveredOutsideLines') : 0;
    updateCoverageCells(container, `.t-totals__${type}`, sumData(attrs.covered), sumData(attrs.total), outside);
  }
}

function updateCoverageCells(
  container: Element,
  prefix: string,
  covered: number,
  total: number,
  outside: number
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
  if (covCell) {
    covCell.innerHTML = `<div class="coverage-cell">${renderCoverageBar(p, (outside * 100.0) / total)}<span class="coverage-pct">${fmtPct(p)}%</span></div>`;
    covCell.classList.remove('green', 'yellow', 'red');
    covCell.classList.add(pctClass(p));
  }
  if (numEl) numEl.textContent = fmtNum(covered) + '/';
  if (denEl) denEl.textContent = fmtNum(total);
}
