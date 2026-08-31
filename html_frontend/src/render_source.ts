
import { escapeHTML } from './dom';
import { fileId } from './format';
import { renderCoverageSummary } from './render_cells';
import { decodeFileContexts, type FileContextIndex } from './contexts';
import type { FileCoverage, BranchEntry, MethodEntry, ProductionFileEntry } from './types';

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

  if (lineCov === 'ignored') return 'skipped';

  if (branchCoverage) {
    const branches = branchesReport[lineNum];
    if (branches && branches.some(([, count]) => count === 0)) return 'missed-branch';
  }

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

const LANGUAGES: Record<string, string> = { erb: 'erb', haml: 'haml', slim: 'slim' };

export function languageFor(filename: string): string {
  return LANGUAGES[filename.split('.').pop()!.toLowerCase()] || 'ruby';
}

interface SourceLineArgs {
  index: number;
  source: string;
  language: string;
  lineCov: number | null | 'ignored' | undefined;
  status: string;
  branchCoverage: boolean;
  lineBranches?: [string, number][];
  testCount?: number;
  productionRan?: boolean;
}

function renderSourceLine(args: SourceLineArgs): string {
  const { index, source, language, lineCov, status, branchCoverage, lineBranches, testCount, productionRan } = args;
  const lineNum = index + 1;
  const hitsAttr = typeof lineCov === 'number' ? ` data-hits="${lineCov}"` : '';
  const productionClass = productionRan === undefined ? '' : (productionRan ? ' production-ran' : ' production-never');
  const lineHtml = [`<li class="${status}${productionClass}"${hitsAttr} data-linenumber="${lineNum}">`];

  if (typeof lineCov === 'number' && lineCov > 0) {
    lineHtml.push(`<span class="hits" data-content="${lineCov}"></span>`);
  } else if (lineCov === 'ignored') {
    lineHtml.push('<span class="hits" data-content="skipped"></span>');
  }

  if (productionRan && lineCov === 0) {
    lineHtml.push('<span class="hits hits--production" data-content="runs in production"></span>');
  }

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

  lineHtml.push(`<code class="${language}">${escapeHTML(source)}</code></li>`);
  return lineHtml.join('');
}

function renderProductionSummary(ran: number, total: number, entry: ProductionFileEntry | null): string {
  let parts = `<div class="t-production-summary">\n    Production: <b>${ran}</b>/${total} relevant lines ran`;
  const stamp = entry && entry.last_seen;
  if (stamp) {
    parts += `<span class="coverage-cell__fraction">, last run ` +
      `<span title="${escapeHTML(stamp)}">${escapeHTML(stamp.slice(0, 10))}</span></span>`;
  }
  return parts + '\n  </div>';
}

export function renderSourceFile(
  filename: string,
  data: FileCoverage,
  lineCoverage: boolean,
  branchCoverage: boolean,
  methodCoverage: boolean,
  contexts?: string[],
  production?: ProductionFileEntry | null
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
  const language = languageFor(filename);
  const contextIndex: FileContextIndex | null =
    contexts ? decodeFileContexts(data.contexts, data.source.length) : null;
  let outsideLines = 0;
  const productionLines = production === undefined ? null : new Set(production ? production.lines : []);
  let productionRanCount = 0;

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
        outsideLines++;
        if (status === 'covered') status = 'outside-tests';
      }
    }
    let productionRan: boolean | undefined;
    if (productionLines && typeof lineCov === 'number') {
      productionRan = productionLines.has(i + 1);
      if (productionRan) productionRanCount++;
    }
    lineRows.push(renderSourceLine({
      index: i,
      source: data.source[i],
      language,
      lineCov,
      status,
      branchCoverage,
      lineBranches: branchCoverage ? branchesReport[i + 1] : undefined,
      testCount,
      productionRan
    }));
  }

  const html = [
    `<div class="source_table" id="${id}">`,
    '<div class="header">',
    `<h2>${escapeHTML(filename)}</h2>`,
    renderCoverageSummary({
      coveredLines, totalLines,
      coveredBranches, totalBranches,
      coveredMethods, totalMethods,
      lineCoverage, branchCoverage, methodCoverage, showMethodToggle,
      coveredByTests: contextIndex ? coveredLines - outsideLines : undefined,
      coveredOutsideTests: contextIndex ? outsideLines : undefined
    })
  ];

  if (production !== undefined) {
    html.push('<div class="summary-stats summary-stats--production">',
              renderProductionSummary(productionRanCount, totalLines, production),
              '</div>');
  }

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
