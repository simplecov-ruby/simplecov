// Per-file source view: classifies each line's coverage status and builds the
// annotated <pre><ol> source listing with its coverage summary header.

import { escapeHTML } from './dom';
import { fileId } from './format';
import { renderCoverageSummary } from './render_cells';
import { decodeFileContexts, type FileContextIndex } from './contexts';
import type { FileCoverage, BranchEntry, MethodEntry } from './types';

interface LineStatusArgs {
  lineIndex: number;
  lineCov: number | null | 'ignored' | undefined;
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

  return lineCov === null || lineCov === undefined ? 'never' : lineCov === 0 ? 'missed' : 'covered';
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
  lineCov: number | null | 'ignored' | undefined;
  status: string;
  branchCoverage: boolean;
  lineBranches?: [string, number][];
  // The covering test count, present only when contexts were recorded
  // and the line executed.
  testCount?: number;
}

function renderSourceLine(args: SourceLineArgs): string {
  const { index, source, lineCov, status, branchCoverage, lineBranches, testCount } = args;
  const lineNum = index + 1;
  const hitsAttr = typeof lineCov === 'number' ? ` data-hits="${lineCov}"` : '';
  const lineHtml = [`<li class="${status}"${hitsAttr} data-linenumber="${lineNum}">`];

  if (typeof lineCov === 'number' && lineCov > 0) {
    lineHtml.push(`<span class="hits" data-content="${lineCov}"></span>`);
  } else if (lineCov === 'ignored') {
    lineHtml.push('<span class="hits" data-content="skipped"></span>');
  }

  // A real button so the peek panel it opens is keyboard-reachable. The
  // count is written out in words — the badge next to a bare hit number
  // must explain itself, and the report deliberately carries no glyphs.
  if (testCount !== undefined) {
    const none = testCount === 0 ? ' hits--tests-none' : '';
    const label = testCount === 1 ? '1 test' : `${testCount} tests`;
    lineHtml.push(
      `<button type="button" class="hits hits--tests${none}" data-content="${label}"` +
      ` data-tests-line="${lineNum}" title="List the tests covering this line" aria-expanded="false"></button>`
    );
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

// The `t-tests-summary` header row: how many recorded tests touch the
// file, and how many covered lines none of them executed.
function renderTestsSummary(distinct: number, outsideLines: number): string {
  const tests = distinct === 1 ? '<b>1 test</b> covers' : `<b>${distinct} tests</b> cover`;
  let html = `<div class="t-tests-summary">\n    Test coverage: ${tests} this file`;
  if (outsideLines > 0) {
    const lines = outsideLines === 1 ? '1 line' : `${outsideLines} lines`;
    html += `, <span class="outside-tests-text"><b>${lines}</b> covered outside tests</span>`;
  }
  return html + '\n  </div>';
}

export function renderSourceFile(
  filename: string,
  data: FileCoverage,
  lineCoverage: boolean,
  branchCoverage: boolean,
  methodCoverage: boolean,
  contexts?: string[]
): string {
  const id = fileId(filename);
  const coveredLines = lineCoverage ? (data.covered_lines || 0) : 0;
  const totalLines = lineCoverage ? (data.total_lines || 0) : 0;
  const coveredBranches = branchCoverage ? (data.covered_branches || 0) : 0;
  const totalBranches = branchCoverage ? (data.total_branches || 0) : 0;
  const coveredMethods = methodCoverage ? (data.covered_methods || 0) : 0;
  const totalMethods = methodCoverage ? (data.total_methods || 0) : 0;

  const missedMethodsList = (data.methods || []).filter(m => m.coverage === 0);
  const showMethodToggle = methodCoverage && missedMethodsList.length > 0;

  const branchesReport = buildBranchesReport(data.branches);
  const missedMethodLineSet = buildMissedMethodLines(data.methods);
  const contextIndex: FileContextIndex | null =
    contexts ? decodeFileContexts(data.contexts, data.source.length) : null;
  let outsideLines = 0;

  // Lines render before the header: the tests summary needs the drained
  // line count, which only the line pass knows.
  const lineRows: string[] = [];
  for (let i = 0; i < data.source.length; i++) {
    const lineCov = data.lines?.[i];
    let status = lineStatus({
      lineIndex: i, lineCov, branchesReport,
      missedMethodLines: missedMethodLineSet, branchCoverage, methodCoverage
    });
    let testCount: number | undefined;
    if (contextIndex && typeof lineCov === 'number' && lineCov > 0) {
      testCount = contextIndex.perLine[i].length;
      if (testCount === 0) {
        // The count states the attribution fact for every covered line,
        // matching the file list's grey bar share. The drain itself only
        // claims a plain covered line: branch and method misses stay
        // ranked above it — they name a problem, this names an absence.
        outsideLines++;
        if (status === 'covered') status = 'outside-tests';
      }
    }
    lineRows.push(renderSourceLine({
      index: i,
      source: data.source[i],
      lineCov,
      status,
      branchCoverage,
      lineBranches: branchCoverage ? branchesReport[i + 1] : undefined,
      testCount
    }));
  }
  const testsSummary = contextIndex
    ? renderTestsSummary(contextIndex.distinct, outsideLines)
    : undefined;

  const html = [
    `<div class="source_table" id="${id}">`,
    '<div class="header">',
    `<h2>${escapeHTML(filename)}</h2>`,
    renderCoverageSummary({
      coveredLines, totalLines,
      coveredBranches, totalBranches,
      coveredMethods, totalMethods,
      lineCoverage, branchCoverage, methodCoverage, showMethodToggle,
      testsSummary
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
  html.push(...lineRows);
  html.push('</ol></pre></div>');
  return html.join('');
}
