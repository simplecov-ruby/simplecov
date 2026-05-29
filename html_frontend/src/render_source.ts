// Per-file source view: classifies each line's coverage status and builds the
// annotated <pre><ol> source listing with its coverage summary header.

import { escapeHTML } from './dom';
import { fileId } from './format';
import { renderCoverageSummary } from './render_cells';
import type { FileCoverage, BranchEntry, MethodEntry } from './types';

interface LineStatusArgs {
  lineIndex: number;
  lineCov: number | null | 'ignored';
  branchesReport: Record<number, [string, number][]>;
  missedMethodLines: Set<number>;
  branchCoverage: boolean;
  methodCoverage: boolean;
}

function lineStatus(args: LineStatusArgs): string {
  const { lineIndex, lineCov, branchesReport, missedMethodLines, branchCoverage, methodCoverage } = args;
  const lineNum = lineIndex + 1;

  // Check basic status
  if (lineCov === 'ignored') return 'skipped';

  // Branch miss takes priority
  if (branchCoverage) {
    const branches = branchesReport[lineNum];
    if (branches && branches.some(([, count]) => count === 0)) return 'missed-branch';
  }

  // Method miss
  if (methodCoverage && missedMethodLines.has(lineNum)) return 'missed-method';

  return lineCov === null ? 'never' : lineCov === 0 ? 'missed' : 'covered';
}

function buildBranchesReport(branches: BranchEntry[] | undefined): Record<number, [string, number][]> {
  const report: Record<number, [string, number][]> = {};
  if (!branches) return report;
  for (const { coverage, report_line: reportLine, type } of branches) {
    if (coverage === 'ignored') continue;
    const lineReport = report[reportLine] || (report[reportLine] = []);
    lineReport.push([type, coverage]);
  }
  return report;
}

function buildMissedMethodLines(methods: MethodEntry[] | undefined): Set<number> {
  const set = new Set<number>();
  if (!methods) return set;
  for (const m of methods) {
    if (m.coverage === 0 && m.start_line && m.end_line) {
      for (let i = m.start_line; i <= m.end_line; i++) set.add(i);
    }
  }
  return set;
}

interface SourceLineArgs {
  index: number;
  source: string;
  lineCov: number | null | 'ignored';
  status: string;
  branchCoverage: boolean;
  lineBranches?: [string, number][];
}

function renderSourceLine(args: SourceLineArgs): string {
  const { index, source, lineCov, status, branchCoverage, lineBranches } = args;
  const lineNum = index + 1;
  const hitsAttr = lineCov !== null && lineCov !== 'ignored' ? ` data-hits="${lineCov}"` : '';
  const lineHtml = [`<li class="${status}"${hitsAttr} data-linenumber="${lineNum}">`];

  if (status === 'covered' || (lineCov !== null && lineCov !== 'ignored' && lineCov !== 0)) {
    lineHtml.push(`<span class="hits" data-content="${lineCov}"></span>`);
  } else if (lineCov === 'ignored') {
    lineHtml.push('<span class="hits" data-content="skipped"></span>');
  }

  if (branchCoverage && lineBranches) {
    for (const [branchType, hitCount] of lineBranches) {
      const label = escapeHTML(branchType);
      lineHtml.push(`<span class="hits" data-content="${label}: ${hitCount}" title="${label} branch hit ${hitCount} times"></span>`);
    }
  }

  lineHtml.push(`<code class="ruby">${escapeHTML(source)}</code></li>`);
  return lineHtml.join('');
}

export function renderSourceFile(filename: string, data: FileCoverage, branchCoverage: boolean, methodCoverage: boolean): string {
  const id = fileId(filename);
  const coveredLines = data.covered_lines;
  const totalLines = data.total_lines;
  const coveredBranches = branchCoverage ? (data.covered_branches || 0) : 0;
  const totalBranches = branchCoverage ? (data.total_branches || 0) : 0;
  const coveredMethods = methodCoverage ? (data.covered_methods || 0) : 0;
  const totalMethods = methodCoverage ? (data.total_methods || 0) : 0;

  const missedMethodsList = (data.methods || []).filter(m => m.coverage === 0);
  const showMethodToggle = methodCoverage && missedMethodsList.length > 0;

  const branchesReport = buildBranchesReport(data.branches);
  const missedMethodLineSet = buildMissedMethodLines(data.methods);

  const html = [
    `<div class="source_table" id="${id}">`,
    '<div class="header">',
    `<h2>${escapeHTML(filename)}</h2>`,
    renderCoverageSummary({
      coveredLines, totalLines,
      coveredBranches, totalBranches,
      coveredMethods, totalMethods,
      branchCoverage, methodCoverage, showMethodToggle
    })
  ];

  if (showMethodToggle) {
    html.push(
      '<div class="t-missed-method-list" style="display: none"><ul>',
      missedMethodsList.map((m) => `<li><tt>${escapeHTML(m.name)}</tt></li>`).join(''),
      '</ul></div>'
    );
  }
  html.push('</div>', '<pre><ol>');

  for (let i = 0; i < data.source.length; i++) {
    const lineCov = data.lines[i];
    const status = lineStatus({
      lineIndex: i, lineCov, branchesReport,
      missedMethodLines: missedMethodLineSet, branchCoverage, methodCoverage
    });
    html.push(renderSourceLine({
      index: i,
      source: data.source[i],
      lineCov,
      status,
      branchCoverage,
      lineBranches: branchCoverage ? branchesReport[i + 1] : undefined
    }));
  }
  html.push('</ol></pre></div>');
  return html.join('');
}
