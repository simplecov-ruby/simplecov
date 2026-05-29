// File-list table markup: the per-group container, column headers, totals row,
// and one row per source file.

import { escapeHTML } from './dom';
import { pctClass, fmtNum, fmtPct, toHtmlId, fileId } from './format';
import { renderCoverageCells, renderHeaderCells } from './render_cells';
import type { StatGroup, FileCoverage } from './types';

interface FileListArgs {
  title: string;
  filenames: string[];
  stats: StatGroup;
  allCoverage: Record<string, FileCoverage>;
  branchCoverage: boolean;
  methodCoverage: boolean;
}

// Container open + <thead> (column headers and the totals row), i.e.
// everything in a file-list section before the per-file <tbody> rows.
function renderFileListHead(args: FileListArgs): string {
  const { title, filenames, stats, branchCoverage, methodCoverage } = args;
  const containerId = toHtmlId(title);
  const lineStats = stats.lines;
  const branchStats = branchCoverage ? stats.branches : undefined;
  const methodStats = methodCoverage ? stats.methods : undefined;

  const html = [
    `<div class="file_list_container" id="${containerId}" data-total-files="${filenames.length}">`,
    `<span class="group_name hide">${escapeHTML(title)}</span>`,
    `<span class="covered_percent hide"><span class="${pctClass(lineStats.percent)}">${fmtPct(lineStats.percent)}%</span></span>`,
    '<div class="file_list--responsive"><table class="file_list"><thead><tr>',
    `<th class="cell--left"><div class="th-with-filter"><span class="th-label">File Name</span><input type="search" class="col-filter col-filter--name" placeholder="Filter paths…"></div></th>`,
    renderHeaderCells('Line Coverage', 'line', 'Covered', 'Lines')
  ];
  if (branchCoverage) html.push(renderHeaderCells('Branch Coverage', 'branch', 'Covered', 'Branches'));
  if (methodCoverage) html.push(renderHeaderCells('Method Coverage', 'method', 'Covered', 'Methods'));
  html.push('</tr>');

  const fileLabel = filenames.length === 1 ? 'file' : 'files';
  html.push(
    `<tr class="totals-row"><td class="strong t-file-count">${fmtNum(filenames.length)} ${fileLabel}</td>`,
    renderCoverageCells(lineStats.percent, lineStats.covered, lineStats.total, 'line', true)
  );
  if (branchStats) html.push(renderCoverageCells(branchStats.percent, branchStats.covered, branchStats.total, 'branch', true));
  if (methodStats) html.push(renderCoverageCells(methodStats.percent, methodStats.covered, methodStats.total, 'method', true));
  html.push('</tr></thead><tbody>');

  return html.join('');
}

interface FileRowArgs {
  filename: string;
  coverage: FileCoverage;
  branchCoverage: boolean;
  methodCoverage: boolean;
}

function renderFileRow(args: FileRowArgs): string {
  const { filename, coverage: f, branchCoverage, methodCoverage } = args;
  const id = fileId(filename);

  const dataAttrs = [
    `data-covered-lines="${f.covered_lines}"`,
    `data-relevant-lines="${f.total_lines}"`
  ];
  if (branchCoverage) {
    dataAttrs.push(`data-covered-branches="${f.covered_branches || 0}"`, `data-total-branches="${f.total_branches || 0}"`);
  }
  if (methodCoverage) {
    dataAttrs.push(`data-covered-methods="${f.covered_methods || 0}"`, `data-total-methods="${f.total_methods || 0}"`);
  }

  const cells = [
    `<tr class="t-file" ${dataAttrs.join(' ')}>`,
    `<td class="strong t-file__name"><a href="#${id}" class="src_link" title="${escapeHTML(filename)}">${escapeHTML(filename)}</a></td>`,
    renderCoverageCells(f.lines_covered_percent, f.covered_lines, f.total_lines, 'line', false)
  ];
  if (branchCoverage) {
    const pct = f.branches_covered_percent === undefined ? 100.0 : f.branches_covered_percent;
    cells.push(renderCoverageCells(pct, f.covered_branches || 0, f.total_branches || 0, 'branch', false));
  }
  if (methodCoverage) {
    const pct = f.methods_covered_percent === undefined ? 100.0 : f.methods_covered_percent;
    cells.push(renderCoverageCells(pct, f.covered_methods || 0, f.total_methods || 0, 'method', false));
  }
  cells.push('</tr>');
  return cells.join('');
}

export function renderFileList(args: FileListArgs): string {
  const { filenames, allCoverage, branchCoverage, methodCoverage } = args;

  const html = [renderFileListHead(args)];
  for (const fn of filenames) {
    const f = allCoverage[fn];
    if (!f) continue;
    html.push(renderFileRow({ filename: fn, coverage: f, branchCoverage, methodCoverage }));
  }
  html.push('</tbody></table></div></div>');
  return html.join('');
}
