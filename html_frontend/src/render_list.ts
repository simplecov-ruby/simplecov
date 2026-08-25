// File-list table markup: the per-group container, column headers, totals row,
// and one row per source file.

import { escapeHTML } from './dom';
import { pctClass, fmtNum, fmtPct, fileId } from './format';
import { primaryCoverageStat } from './coverage';
import { coveredOutsideCount } from './contexts';
import { renderCoverageCells, renderHeaderCells } from './render_cells';
import { renderSparkline, type TrendData } from './sparkline';
import type { CoverageType, StatGroup, FileCoverage } from './types';

interface FileListArgs {
  containerId: string;
  title: string;
  filenames: string[];
  stats: StatGroup;
  allCoverage: Record<string, FileCoverage>;
  lineCoverage: boolean;
  branchCoverage: boolean;
  methodCoverage: boolean;
  primaryCoverage: CoverageType;
  // True when the run recorded contexts (`track_tests`): line bars split
  // out the covered-outside-tests share and pick up the by-tests sort key.
  contextsEnabled?: boolean;
  // The run-history series (see src/sparkline.ts), present only when the
  // report embeds a history; adds the Trend column.
  trend?: TrendData;
}

// Container open + <thead> (column headers and the totals row), i.e.
// everything in a file-list section before the per-file <tbody> rows.
function renderFileListHead(args: FileListArgs, outsideTotal?: number): string {
  const { containerId, title, filenames, stats, lineCoverage, branchCoverage, methodCoverage, primaryCoverage } = args;
  const lineStats = lineCoverage ? stats.lines : undefined;
  const branchStats = branchCoverage ? stats.branches : undefined;
  const methodStats = methodCoverage ? stats.methods : undefined;
  const primaryStats = primaryCoverageStat(stats, primaryCoverage);
  const primaryPercent = primaryStats ? primaryStats.percent : 100.0;

  const html = [
    `<div class="file_list_container" id="${containerId}" data-total-files="${filenames.length}">`,
    `<span class="group_name hide">${escapeHTML(title)}</span>`,
    `<span class="covered_percent hide"><span class="${pctClass(primaryPercent)}">${fmtPct(primaryPercent)}%</span></span>`,
    '<div class="file_list--responsive"><table class="file_list"><thead><tr>',
    `<th class="cell--left" data-sort-key="file"><div class="th-with-filter"><span class="th-label">File Name</span><input type="search" class="col-filter col-filter--name" placeholder="Filter paths…"></div></th>`
  ];
  if (lineStats) html.push(renderHeaderCells('Line Coverage', 'line', 'Covered', 'Lines'));
  if (branchCoverage) html.push(renderHeaderCells('Branch Coverage', 'branch', 'Covered', 'Branches'));
  if (methodCoverage) html.push(renderHeaderCells('Method Coverage', 'method', 'Covered', 'Methods'));
  if (args.trend) html.push('<th class="t-trend-h">Trend</th>');
  html.push('</tr>');

  const fileLabel = filenames.length === 1 ? 'file' : 'files';
  html.push(`<tr class="totals-row"><td class="strong t-file-count">${fmtNum(filenames.length)} ${fileLabel}</td>`);
  if (lineStats) html.push(renderCoverageCells(lineStats.percent, lineStats.covered, lineStats.total, 'line', true, outsideTotal));
  if (branchStats) html.push(renderCoverageCells(branchStats.percent, branchStats.covered, branchStats.total, 'branch', true));
  if (methodStats) html.push(renderCoverageCells(methodStats.percent, methodStats.covered, methodStats.total, 'method', true));
  if (args.trend) html.push(`<td class="t-trend">${renderSparkline(args.trend.totals)}</td>`);
  html.push('</tr></thead><tbody>');

  return html.join('');
}

interface FileRowArgs {
  filename: string;
  coverage: FileCoverage;
  lineCoverage: boolean;
  branchCoverage: boolean;
  methodCoverage: boolean;
  outsideLines?: number;
  // The file's history series; undefined outside trend mode, null-ish
  // (empty cell, column kept aligned) for a file the history never saw.
  trendSeries?: (number | null)[];
  trendEnabled?: boolean;
}

function renderFileRow(args: FileRowArgs): string {
  const { filename, coverage: f, lineCoverage, branchCoverage, methodCoverage, outsideLines } = args;
  const id = fileId(filename);

  const dataAttrs: string[] = [];
  if (lineCoverage) {
    dataAttrs.push(`data-covered-lines="${f.covered_lines || 0}"`, `data-relevant-lines="${f.total_lines || 0}"`);
    if (outsideLines !== undefined) dataAttrs.push(`data-covered-outside-lines="${outsideLines}"`);
  }
  if (branchCoverage) {
    dataAttrs.push(`data-covered-branches="${f.covered_branches || 0}"`, `data-total-branches="${f.total_branches || 0}"`);
  }
  if (methodCoverage) {
    dataAttrs.push(`data-covered-methods="${f.covered_methods || 0}"`, `data-total-methods="${f.total_methods || 0}"`);
  }

  const cells = [
    `<tr class="t-file" ${dataAttrs.join(' ')}>`,
    `<td class="strong t-file__name"><a href="#${id}" class="src_link" title="${escapeHTML(filename)}">${escapeHTML(filename)}</a></td>`
  ];
  if (lineCoverage) {
    const pct = f.lines_covered_percent === undefined ? 100.0 : f.lines_covered_percent;
    cells.push(renderCoverageCells(pct, f.covered_lines || 0, f.total_lines || 0, 'line', false, outsideLines));
  }
  if (branchCoverage) {
    const pct = f.branches_covered_percent === undefined ? 100.0 : f.branches_covered_percent;
    cells.push(renderCoverageCells(pct, f.covered_branches || 0, f.total_branches || 0, 'branch', false));
  }
  if (methodCoverage) {
    const pct = f.methods_covered_percent === undefined ? 100.0 : f.methods_covered_percent;
    cells.push(renderCoverageCells(pct, f.covered_methods || 0, f.total_methods || 0, 'method', false));
  }
  if (args.trendEnabled) cells.push(`<td class="t-trend">${args.trendSeries ? renderSparkline(args.trendSeries) : ''}</td>`);
  cells.push('</tr>');
  return cells.join('');
}

export function renderFileList(args: FileListArgs): string {
  const { filenames, allCoverage, lineCoverage, branchCoverage, methodCoverage, contextsEnabled } = args;

  // Computed once per file: the totals row shows the sum, each row its own.
  const outsideByFile = contextsEnabled && lineCoverage ? new Map(
    filenames.flatMap((fn) => {
      const f = allCoverage[fn];
      return f ? [[fn, coveredOutsideCount(f.contexts, f.lines)] as const] : [];
    })
  ) : undefined;
  const outsideTotal = outsideByFile
    ? [...outsideByFile.values()].reduce((sum, n) => sum + n, 0)
    : undefined;

  const html = [renderFileListHead(args, outsideTotal)];
  for (const fn of filenames) {
    const f = allCoverage[fn];
    if (!f) continue;
    html.push(renderFileRow({
      filename: fn, coverage: f, lineCoverage, branchCoverage, methodCoverage,
      outsideLines: outsideByFile?.get(fn),
      trendSeries: args.trend?.files.get(fn),
      trendEnabled: !!args.trend
    }));
  }
  html.push('</tbody></table></div></div>');
  return html.join('');
}
