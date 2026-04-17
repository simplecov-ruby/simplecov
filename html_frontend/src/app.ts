import hljs from 'highlight.js/lib/core';
import ruby from 'highlight.js/lib/languages/ruby';

hljs.registerLanguage('ruby', ruby);

// --- Types for coverage data ---------------------------------

interface CoverageData {
  meta: {
    simplecov_version: string;
    command_name: string;
    project_name: string;
    timestamp: string;
    root: string;
    branch_coverage: boolean;
    method_coverage: boolean;
  };
  total: StatGroup;
  coverage: Record<string, FileCoverage>;
  groups: Record<string, GroupData>;
}

interface StatGroup {
  lines: CoverageStat;
  branches?: CoverageStat;
  methods?: CoverageStat;
}

interface CoverageStat {
  covered: number;
  missed: number;
  total: number;
  percent: number;
  strength: number;
}

interface FileCoverage {
  lines: (number | null | 'ignored')[];
  source: string[];
  lines_covered_percent: number;
  covered_lines: number;
  missed_lines: number;
  branches?: BranchEntry[];
  branches_covered_percent?: number;
  covered_branches?: number;
  missed_branches?: number;
  total_branches?: number;
  methods?: MethodEntry[];
  methods_covered_percent?: number;
  covered_methods?: number;
  missed_methods?: number;
  total_methods?: number;
}

interface BranchEntry {
  type: string;
  start_line: number;
  end_line: number;
  coverage: number | 'ignored';
  inline: boolean;
  report_line: number;
}

interface MethodEntry {
  name: string;
  start_line: number;
  end_line: number;
  coverage: number | 'ignored';
}

interface GroupData {
  lines: CoverageStat;
  branches?: CoverageStat;
  methods?: CoverageStat;
  files?: string[];
}

declare global {
  interface Window {
    SIMPLECOV_DATA: CoverageData;
  }
}

// --- Constants ------------------------------------------------

const MAX_BAR_WIDTH = 240;
const MIN_BAR_WIDTH = 160;
const GREEN_THRESHOLD = 90;
const YELLOW_THRESHOLD = 75;

// --- Utility helpers ------------------------------------------

function $(sel: string, ctx?: Element | Document): Element | null {
  return (ctx || document).querySelector(sel);
}

function $$(sel: string, ctx?: Element | Document): Element[] {
  return Array.from((ctx || document).querySelectorAll(sel));
}

function on(
  target: EventTarget,
  event: string,
  selectorOrFn: string | ((e: Event) => void),
  fn?: (this: Element, e: Event) => void
): void {
  if (typeof selectorOrFn === 'function') {
    target.addEventListener(event, selectorOrFn);
  } else {
    target.addEventListener(event, function (e: Event) {
      const el = (e.target as Element).closest(selectorOrFn);
      if (el && (target as Element).contains(el) && fn) {
        fn.call(el, e);
      }
    });
  }
}

function escapeHTML(str: string): string {
  const div = document.createElement('div');
  div.appendChild(document.createTextNode(str));
  return div.innerHTML;
}

function md5Hex(str: string): string {
  // Simple string hash that matches Ruby's Digest::MD5.hexdigest output format.
  // We use the Web Crypto API is not available synchronously, so we use a
  // JS implementation of MD5 for deterministic, synchronous hashing.
  return md5(str);
}

// Minimal MD5 implementation (RFC 1321) for file ID hashing.
// Produces the same hex digest as Ruby's Digest::MD5.hexdigest.
function md5(str: string): string {
  function safeAdd(x: number, y: number): number {
    const lsw = (x & 0xFFFF) + (y & 0xFFFF);
    return (((x >> 16) + (y >> 16) + (lsw >> 16)) << 16) | (lsw & 0xFFFF);
  }
  function bitRotateLeft(num: number, cnt: number): number {
    return (num << cnt) | (num >>> (32 - cnt));
  }
  function md5cmn(q: number, a: number, b: number, x: number, s: number, t: number): number {
    return safeAdd(bitRotateLeft(safeAdd(safeAdd(a, q), safeAdd(x, t)), s), b);
  }
  function md5ff(a: number, b: number, c: number, d: number, x: number, s: number, t: number): number {
    return md5cmn((b & c) | ((~b) & d), a, b, x, s, t);
  }
  function md5gg(a: number, b: number, c: number, d: number, x: number, s: number, t: number): number {
    return md5cmn((b & d) | (c & (~d)), a, b, x, s, t);
  }
  function md5hh(a: number, b: number, c: number, d: number, x: number, s: number, t: number): number {
    return md5cmn(b ^ c ^ d, a, b, x, s, t);
  }
  function md5ii(a: number, b: number, c: number, d: number, x: number, s: number, t: number): number {
    return md5cmn(c ^ (b | (~d)), a, b, x, s, t);
  }

  // Convert string to UTF-8 bytes, correctly handling surrogate pairs/non-BMP characters
  const bytes: number[] = Array.from(new TextEncoder().encode(str));
  const len = bytes.length;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  const bitLen = len * 8;
  bytes.push(bitLen & 0xff, (bitLen >> 8) & 0xff, (bitLen >> 16) & 0xff, (bitLen >> 24) & 0xff);
  bytes.push(0, 0, 0, 0); // high 32 bits of length (always 0 for strings)

  const words: number[] = [];
  for (let i = 0; i < bytes.length; i += 4) {
    words.push(bytes[i] | (bytes[i + 1] << 8) | (bytes[i + 2] << 16) | (bytes[i + 3] << 24));
  }

  let a = 0x67452301, b = 0xefcdab89, c = 0x98badcfe, d = 0x10325476;
  for (let i = 0; i < words.length; i += 16) {
    const aa = a, bb = b, cc = c, dd = d;
    const x = words.slice(i, i + 16);
    a = md5ff(a, b, c, d, x[0], 7, -680876936); d = md5ff(d, a, b, c, x[1], 12, -389564586);
    c = md5ff(c, d, a, b, x[2], 17, 606105819); b = md5ff(b, c, d, a, x[3], 22, -1044525330);
    a = md5ff(a, b, c, d, x[4], 7, -176418897); d = md5ff(d, a, b, c, x[5], 12, 1200080426);
    c = md5ff(c, d, a, b, x[6], 17, -1473231341); b = md5ff(b, c, d, a, x[7], 22, -45705983);
    a = md5ff(a, b, c, d, x[8], 7, 1770035416); d = md5ff(d, a, b, c, x[9], 12, -1958414417);
    c = md5ff(c, d, a, b, x[10], 17, -42063); b = md5ff(b, c, d, a, x[11], 22, -1990404162);
    a = md5ff(a, b, c, d, x[12], 7, 1804603682); d = md5ff(d, a, b, c, x[13], 12, -40341101);
    c = md5ff(c, d, a, b, x[14], 17, -1502002290); b = md5ff(b, c, d, a, x[15], 22, 1236535329);
    a = md5gg(a, b, c, d, x[1], 5, -165796510); d = md5gg(d, a, b, c, x[6], 9, -1069501632);
    c = md5gg(c, d, a, b, x[11], 14, 643717713); b = md5gg(b, c, d, a, x[0], 20, -373897302);
    a = md5gg(a, b, c, d, x[5], 5, -701558691); d = md5gg(d, a, b, c, x[10], 9, 38016083);
    c = md5gg(c, d, a, b, x[15], 14, -660478335); b = md5gg(b, c, d, a, x[4], 20, -405537848);
    a = md5gg(a, b, c, d, x[9], 5, 568446438); d = md5gg(d, a, b, c, x[14], 9, -1019803690);
    c = md5gg(c, d, a, b, x[3], 14, -187363961); b = md5gg(b, c, d, a, x[8], 20, 1163531501);
    a = md5gg(a, b, c, d, x[13], 5, -1444681467); d = md5gg(d, a, b, c, x[2], 9, -51403784);
    c = md5gg(c, d, a, b, x[7], 14, 1735328473); b = md5gg(b, c, d, a, x[12], 20, -1926607734);
    a = md5hh(a, b, c, d, x[5], 4, -378558); d = md5hh(d, a, b, c, x[8], 11, -2022574463);
    c = md5hh(c, d, a, b, x[11], 16, 1839030562); b = md5hh(b, c, d, a, x[14], 23, -35309556);
    a = md5hh(a, b, c, d, x[1], 4, -1530992060); d = md5hh(d, a, b, c, x[4], 11, 1272893353);
    c = md5hh(c, d, a, b, x[7], 16, -155497632); b = md5hh(b, c, d, a, x[10], 23, -1094730640);
    a = md5hh(a, b, c, d, x[13], 4, 681279174); d = md5hh(d, a, b, c, x[0], 11, -358537222);
    c = md5hh(c, d, a, b, x[3], 16, -722521979); b = md5hh(b, c, d, a, x[6], 23, 76029189);
    a = md5hh(a, b, c, d, x[9], 4, -640364487); d = md5hh(d, a, b, c, x[12], 11, -421815835);
    c = md5hh(c, d, a, b, x[15], 16, 530742520); b = md5hh(b, c, d, a, x[2], 23, -995338651);
    a = md5ii(a, b, c, d, x[0], 6, -198630844); d = md5ii(d, a, b, c, x[7], 10, 1126891415);
    c = md5ii(c, d, a, b, x[14], 15, -1416354905); b = md5ii(b, c, d, a, x[5], 21, -57434055);
    a = md5ii(a, b, c, d, x[12], 6, 1700485571); d = md5ii(d, a, b, c, x[3], 10, -1894986606);
    c = md5ii(c, d, a, b, x[10], 15, -1051523); b = md5ii(b, c, d, a, x[1], 21, -2054922799);
    a = md5ii(a, b, c, d, x[8], 6, 1873313359); d = md5ii(d, a, b, c, x[15], 10, -30611744);
    c = md5ii(c, d, a, b, x[6], 15, -1560198380); b = md5ii(b, c, d, a, x[13], 21, 1309151649);
    a = md5ii(a, b, c, d, x[4], 6, -145523070); d = md5ii(d, a, b, c, x[11], 10, -1120210379);
    c = md5ii(c, d, a, b, x[2], 15, 718787259); b = md5ii(b, c, d, a, x[9], 21, -343485551);
    a = safeAdd(a, aa); b = safeAdd(b, bb); c = safeAdd(c, cc); d = safeAdd(d, dd);
  }
  const hex = '0123456789abcdef';
  let out = '';
  for (const v of [a, b, c, d]) {
    for (let i = 0; i < 4; i++) {
      out += hex[(v >> (i * 8 + 4)) & 0xF] + hex[(v >> (i * 8)) & 0xF];
    }
  }
  return out;
}

// --- Timeago --------------------------------------------------

// Thresholds in seconds and their display unit.  Ordered largest-first so
// the first match wins.
const TIMEAGO_INTERVALS: [number, string][] = [
  [31536000, 'year'], [2592000, 'month'], [86400, 'day'],
  [3600, 'hour'], [60, 'minute'], [1, 'second']
];

function timeago(date: Date): string {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  for (const [secs, label] of TIMEAGO_INTERVALS) {
    const count = Math.floor(seconds / secs);
    if (count >= 1) {
      return count === 1 ? `about 1 ${label} ago` : `${count} ${label}s ago`;
    }
  }
  return 'just now';
}

// Returns the number of milliseconds until the displayed timeago text would
// change for the given date.  For example, if "3 minutes ago" is displayed,
// the text won't change until the 4th minute boundary, so we return the
// remaining ms until that boundary (plus a small buffer).
function timeagoNextTick(date: Date): number {
  const elapsedSec = (Date.now() - date.getTime()) / 1000;
  for (const [secs] of TIMEAGO_INTERVALS) {
    const count = Math.floor(elapsedSec / secs);
    if (count >= 1) {
      // The text will next change when elapsed reaches (count + 1) * secs
      const nextBoundary = (count + 1) * secs;
      // Add 500ms buffer so we land just after the boundary, not right on it
      return Math.max((nextBoundary - elapsedSec) * 1000 + 500, 1000);
    }
  }
  // Currently "just now" — update in 1 second (when it becomes "1 second ago")
  return 1000;
}

// --- Coverage helpers -----------------------------------------

function pctClass(pct: number): string {
  if (pct >= GREEN_THRESHOLD) return 'green';
  if (pct >= YELLOW_THRESHOLD) return 'yellow';
  return 'red';
}

function fmtNum(n: number): string {
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

function fmtPct(pct: number): string {
  return (Math.floor(pct * 100) / 100).toFixed(2);
}

function fileId(filename: string): string {
  return md5Hex(filename);
}

function toHtmlId(value: string): string {
  return value.replace(/^[^a-zA-Z]+/, '').replace(/[^a-zA-Z0-9\-_]/g, '');
}

// --- Coverage rendering helpers -------------------------------

function renderCoverageBar(pct: number): string {
  const css = pctClass(pct);
  const width = fmtPct(pct);
  return `<div class="bar-sizer"><div class="coverage-bar"><div class="coverage-bar__fill coverage-bar__fill--${css}" style="width: ${width}%"></div></div></div>`;
}

function renderCoverageCells(pct: number, covered: number, total: number, type: string, totals: boolean): string {
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

function renderHeaderCells(label: string, type: string, coveredLabel: string, totalLabel: string): string {
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

// --- Rendering: Coverage summary (per source file) ------------

function renderTypeSummary(type: string, label: string, covered: number, total: number, enabled: boolean, opts: { suffix?: string; missedClass?: string; toggle?: boolean } = {}): string {
  if (!enabled) {
    return `<div class="t-${type}-summary">\n    ${label}: <span class="coverage-disabled">disabled</span>\n  </div>`;
  }
  const missed = total - covered;
  const pct = total > 0 ? (covered * 100.0 / total) : 100.0;
  const css = pctClass(pct);
  const suffix = opts.suffix || 'covered';
  const missedClass = opts.missedClass || 'red';

  let parts = `<div class="t-${type}-summary">\n    ${label}: ` +
    `<span class="${css}"><b>${fmtPct(pct)}%</b></span>` +
    `<span class="coverage-cell__fraction"> ${covered}/${total} ${suffix}</span>`;

  if (missed > 0) {
    const missedHtml = opts.toggle
      ? `<a href="#" class="t-missed-method-toggle"><b>${missed}</b> missed</a>`
      : `<span class="${missedClass}"><b>${missed}</b> missed</span>`;
    parts += `<span class="coverage-cell__fraction">,</span>\n    ${missedHtml}`;
  }
  parts += '\n  </div>';
  return parts;
}

function renderCoverageSummary(
  coveredLines: number, totalLines: number,
  coveredBranches: number, totalBranches: number,
  coveredMethods: number, totalMethods: number,
  branchCoverage: boolean, methodCoverage: boolean,
  showMethodToggle: boolean
): string {
  return '<div class="summary-stats">' +
    renderTypeSummary('line', 'Line coverage', coveredLines, totalLines, true, { suffix: 'relevant lines covered' }) +
    renderTypeSummary('branch', 'Branch coverage', coveredBranches, totalBranches, branchCoverage, { missedClass: 'missed-branch-text' }) +
    renderTypeSummary('method', 'Method coverage', coveredMethods, totalMethods, methodCoverage, { missedClass: 'missed-method-text-color', toggle: showMethodToggle }) +
    '</div>';
}

// --- Rendering: Source file view ------------------------------

function lineStatus(
  lineIndex: number,
  lineCov: number | null | 'ignored',
  branchesReport: Record<number, [string, number][]>,
  missedMethodLines: Set<number>,
  branchCoverage: boolean,
  methodCoverage: boolean
): string {
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

  if (lineCov === null) return 'never';
  if (lineCov === 0) return 'missed';
  return 'covered';
}

function buildBranchesReport(branches: BranchEntry[] | undefined): Record<number, [string, number][]> {
  const report: Record<number, [string, number][]> = {};
  if (!branches) return report;
  for (const b of branches) {
    if (b.coverage === 'ignored') continue;
    if (!report[b.report_line]) report[b.report_line] = [];
    report[b.report_line].push([b.type, b.coverage as number]);
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

function renderSourceFile(filename: string, data: FileCoverage, branchCoverage: boolean, methodCoverage: boolean): string {
  const id = fileId(filename);
  const coveredLines = data.covered_lines;
  const missedLines = data.missed_lines;
  const totalLines = coveredLines + missedLines;
  const coveredBranches = branchCoverage ? (data.covered_branches || 0) : 0;
  const totalBranches = branchCoverage ? (data.total_branches || 0) : 0;
  const coveredMethods = methodCoverage ? (data.covered_methods || 0) : 0;
  const totalMethods = methodCoverage ? (data.total_methods || 0) : 0;

  const missedMethodsList = (data.methods || []).filter(m => m.coverage === 0);
  const showMethodToggle = methodCoverage && missedMethodsList.length > 0;

  const branchesReport = buildBranchesReport(data.branches);
  const missedMethodLineSet = buildMissedMethodLines(data.methods);

  let html = `<div class="source_table" id="${id}">`;
  html += '<div class="header">';
  html += `<h2>${escapeHTML(filename)}</h2>`;
  html += renderCoverageSummary(coveredLines, totalLines, coveredBranches, totalBranches, coveredMethods, totalMethods, branchCoverage, methodCoverage, showMethodToggle);

  if (showMethodToggle) {
    html += '<div class="t-missed-method-list" style="display: none"><ul>';
    for (const m of missedMethodsList) {
      html += `<li><tt>${escapeHTML(m.name)}</tt></li>`;
    }
    html += '</ul></div>';
  }
  html += '</div>';

  // Source lines
  html += '<pre><ol>';
  for (let i = 0; i < data.source.length; i++) {
    const lineCov = data.lines[i];
    const status = lineStatus(i, lineCov, branchesReport, missedMethodLineSet, branchCoverage, methodCoverage);
    const lineNum = i + 1;
    const hitsAttr = lineCov !== null && lineCov !== 'ignored' ? ` data-hits="${lineCov}"` : '';

    html += `<li class="${status}"${hitsAttr} data-linenumber="${lineNum}">`;

    if (status === 'covered' || (lineCov !== null && lineCov !== 'ignored' && lineCov !== 0)) {
      html += `<span class="hits" data-content="${lineCov}"></span>`;
    } else if (lineCov === 'ignored') {
      html += '<span class="hits" data-content="skipped"></span>';
    }

    if (branchCoverage) {
      const lineBranches = branchesReport[lineNum];
      if (lineBranches) {
        for (const [branchType, hitCount] of lineBranches) {
          html += `<span class="hits" data-content="${branchType}: ${hitCount}" title="${branchType} branch hit ${hitCount} times"></span>`;
        }
      }
    }

    html += `<code class="ruby">${escapeHTML(data.source[i])}</code></li>`;
  }
  html += '</ol></pre></div>';
  return html;
}

// --- Rendering: File list table --------------------------------

function renderFileList(
  title: string,
  filenames: string[],
  allCoverage: Record<string, FileCoverage>,
  branchCoverage: boolean,
  methodCoverage: boolean
): string {
  const containerId = toHtmlId(title);

  // Compute totals across all files in this list
  let totalCoveredLines = 0, totalRelevantLines = 0;
  let totalCoveredBranches = 0, totalAllBranches = 0;
  let totalCoveredMethods = 0, totalAllMethods = 0;

  for (const fn of filenames) {
    const f = allCoverage[fn];
    if (!f) continue;
    totalCoveredLines += f.covered_lines;
    totalRelevantLines += f.covered_lines + f.missed_lines;
    if (branchCoverage) {
      totalCoveredBranches += f.covered_branches || 0;
      totalAllBranches += f.total_branches || 0;
    }
    if (methodCoverage) {
      totalCoveredMethods += f.covered_methods || 0;
      totalAllMethods += f.total_methods || 0;
    }
  }

  const linePct = totalRelevantLines > 0 ? totalCoveredLines * 100.0 / totalRelevantLines : 100.0;
  const branchPct = branchCoverage && totalAllBranches > 0 ? totalCoveredBranches * 100.0 / totalAllBranches : 100.0;
  const methodPct = methodCoverage && totalAllMethods > 0 ? totalCoveredMethods * 100.0 / totalAllMethods : 100.0;

  let html = `<div class="file_list_container" id="${containerId}" data-total-files="${filenames.length}">`;
  html += `<span class="group_name hide">${escapeHTML(title)}</span>`;
  html += `<span class="covered_percent hide"><span class="${pctClass(linePct)}">${fmtPct(linePct)}%</span></span>`;

  html += '<div class="file_list--responsive"><table class="file_list"><thead><tr>';
  html += `<th class="cell--left"><div class="th-with-filter"><span class="th-label">File Name</span><input type="search" class="col-filter col-filter--name" placeholder="Filter paths\u2026"></div></th>`;
  html += renderHeaderCells('Line Coverage', 'line', 'Covered', 'Lines');
  if (branchCoverage) html += renderHeaderCells('Branch Coverage', 'branch', 'Covered', 'Branches');
  if (methodCoverage) html += renderHeaderCells('Method Coverage', 'method', 'Covered', 'Methods');
  html += '</tr>';

  // Totals row
  const fileLabel = filenames.length === 1 ? 'file' : 'files';
  html += `<tr class="totals-row"><td class="strong t-file-count">${fmtNum(filenames.length)} ${fileLabel}</td>`;
  html += renderCoverageCells(linePct, totalCoveredLines, totalRelevantLines, 'line', true);
  if (branchCoverage) html += renderCoverageCells(branchPct, totalCoveredBranches, totalAllBranches, 'branch', true);
  if (methodCoverage) html += renderCoverageCells(methodPct, totalCoveredMethods, totalAllMethods, 'method', true);
  html += '</tr></thead><tbody>';

  // File rows
  for (const fn of filenames) {
    const f = allCoverage[fn];
    if (!f) continue;
    const id = fileId(fn);
    const coveredLines = f.covered_lines;
    const relevantLines = coveredLines + f.missed_lines;

    let dataAttrs = `data-covered-lines="${coveredLines}" data-relevant-lines="${relevantLines}"`;
    if (branchCoverage) {
      dataAttrs += ` data-covered-branches="${f.covered_branches || 0}" data-total-branches="${f.total_branches || 0}"`;
    }
    if (methodCoverage) {
      dataAttrs += ` data-covered-methods="${f.covered_methods || 0}" data-total-methods="${f.total_methods || 0}"`;
    }

    html += `<tr class="t-file" ${dataAttrs}>`;
    html += `<td class="strong t-file__name"><a href="#${id}" class="src_link" title="${escapeHTML(fn)}">${escapeHTML(fn)}</a></td>`;
    html += renderCoverageCells(f.lines_covered_percent, coveredLines, relevantLines, 'line', false);
    if (branchCoverage) {
      html += renderCoverageCells(f.branches_covered_percent || 100.0, f.covered_branches || 0, f.total_branches || 0, 'branch', false);
    }
    if (methodCoverage) {
      html += renderCoverageCells(f.methods_covered_percent || 100.0, f.covered_methods || 0, f.total_methods || 0, 'method', false);
    }
    html += '</tr>';
  }

  html += '</tbody></table></div></div>';
  return html;
}

// --- Rendering: Full page from data ---------------------------

function renderPage(data: CoverageData): void {
  const meta = data.meta;
  const branchCoverage = meta.branch_coverage;
  const methodCoverage = meta.method_coverage;

  // Page title and favicon
  document.title = `Code coverage for ${meta.project_name}`;
  const allFiles = Object.keys(data.coverage);
  const overallPct = data.total.lines.total > 0 ? data.total.lines.percent : 100.0;
  const faviconLink = document.createElement('link');
  faviconLink.rel = 'icon';
  faviconLink.type = 'image/png';
  faviconLink.href = `favicon_${pctClass(overallPct)}.png`;
  document.head.appendChild(faviconLink);

  if (branchCoverage) document.body.setAttribute('data-branch-coverage', 'true');

  // Content: file lists
  const content = document.getElementById('content')!;
  content.innerHTML = renderFileList('All Files', allFiles, data.coverage, branchCoverage, methodCoverage);

  for (const groupName of Object.keys(data.groups)) {
    const groupFiles = data.groups[groupName].files || [];
    content.innerHTML += renderFileList(groupName, groupFiles, data.coverage, branchCoverage, methodCoverage);
  }

  // Build id → filename lookup map for O(1) source file materialization
  const idToFilename: Record<string, string> = {};
  for (const fn of allFiles) {
    idToFilename[fileId(fn)] = fn;
  }
  (window as any)._simplecovIdMap = idToFilename;
  (window as any)._simplecovFiles = data.coverage;
  (window as any)._simplecovBranchCoverage = branchCoverage;
  (window as any)._simplecovMethodCoverage = methodCoverage;

  // Footer
  const timestamp = new Date(meta.timestamp);
  const footer = document.getElementById('footer')!;
  footer.innerHTML = `Generated <abbr class="timeago" title="${timestamp.toISOString()}">${timestamp.toISOString()}</abbr>` +
    ` by <a href="https://github.com/simplecov-ruby/simplecov">simplecov</a> v${escapeHTML(meta.simplecov_version)}` +
    ` using ${escapeHTML(meta.command_name)}`;

  // Source legend
  const legend = document.getElementById('source-legend')!;
  let legendHtml = '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--covered"></span>Covered</span>' +
    '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--skipped"></span>Skipped</span>' +
    '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--missed"></span>Missed line</span>';
  if (branchCoverage) {
    legendHtml += '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--missed-branch"></span>Missed branch</span>';
  }
  if (methodCoverage) {
    legendHtml += '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--missed-method"></span>Missed method</span>';
  }
  legend.innerHTML = legendHtml;
}


// --- Sort state -----------------------------------------------

interface SortEntry {
  colIndex: number;
  direction: 'asc' | 'desc';
}

const sortState: Record<string, SortEntry> = {};

function getVisibleChild(row: Element, index: number): Element | null {
  let count = 0;
  for (let i = 0; i < row.children.length; i++) {
    if ((row.children[i] as HTMLElement).style.display === 'none') continue;
    if (count === index) return row.children[i];
    count++;
  }
  return null;
}

function getSortValue(td: Element | null): number | string {
  if (!td) return '';
  const order = td.getAttribute('data-order');
  if (order !== null) return parseFloat(order);
  const text = (td.textContent || '').trim();
  const num = parseFloat(text);
  return isNaN(num) ? text.toLowerCase() : num;
}

function sortTable(table: Element, colIndex: number): void {
  const tableId = table.id || table.getAttribute('data-sort-id') || 'default';
  const state = sortState[tableId] || {} as SortEntry;

  const dir: 'asc' | 'desc' =
    state.colIndex === colIndex && state.direction === 'asc' ? 'desc' : 'asc';
  sortState[tableId] = { colIndex, direction: dir };

  const tbody = table.querySelector('tbody')!;
  const rows = Array.from(tbody.querySelectorAll('tr.t-file'));

  rows.sort((a, b) => {
    const aVal = getSortValue(getVisibleChild(a, colIndex));
    const bVal = getSortValue(getVisibleChild(b, colIndex));
    let cmp: number;
    if (typeof aVal === 'number' && typeof bVal === 'number') {
      cmp = aVal - bVal;
    } else {
      cmp = String(aVal).localeCompare(String(bVal));
    }
    return dir === 'asc' ? cmp : -cmp;
  });

  tbody.append(...rows);

  // Update sort indicators
  let tdPos = 0;
  $$('thead tr:first-child th', table).forEach((th) => {
    const span = parseInt(th.getAttribute('colspan') || '1', 10);
    th.classList.remove('sorting_asc', 'sorting_desc', 'sorting');
    const isActive = colIndex >= tdPos && colIndex < tdPos + span;
    th.classList.add(isActive ? (dir === 'asc' ? 'sorting_asc' : 'sorting_desc') : 'sorting');
    tdPos += span;
  });
}

// --- Column filter types --------------------------------------

interface DataAttrPair {
  covered: string;
  total: string;
}

interface ActiveFilter {
  attrs: DataAttrPair;
  op: string;
  threshold: number;
}

const dataAttrMap: Record<string, DataAttrPair> = {
  line:   { covered: 'coveredLines',   total: 'relevantLines' },
  branch: { covered: 'coveredBranches', total: 'totalBranches' },
  method: { covered: 'coveredMethods',  total: 'totalMethods' }
};

const comparators: Record<string, (value: number, threshold: number) => boolean> = {
  gt:  (v, t) => v > t,
  gte: (v, t) => v >= t,
  eq:  (v, t) => v === t,
  lte: (v, t) => v <= t,
  lt:  (v, t) => v < t,
};

function compare(op: string, value: number, threshold: number): boolean {
  return (comparators[op] || (() => true))(value, threshold);
}

// --- Filter & totals ------------------------------------------

function parseFilters(container: Element): ActiveFilter[] {
  return $$('.col-filter__value', container)
    .map((input: Element) => {
      const inp = input as HTMLInputElement;
      if (!inp.value) return null;
      const threshold = parseFloat(inp.value);
      if (isNaN(threshold)) return null;
      const type = inp.dataset.type || '';
      const opSelect = $(`.col-filter__op[data-type="${type}"]`, container) as HTMLSelectElement | null;
      const op = opSelect ? opSelect.value : '';
      if (!op) return null;
      const attrs = dataAttrMap[type];
      if (!attrs) return null;
      return { attrs, op, threshold } as ActiveFilter;
    })
    .filter((f): f is ActiveFilter => f !== null);
}

function filterTable(container: Element): void {
  const table = $('table.file_list', container) as HTMLTableElement | null;
  if (!table) return;

  const nameInput = $('.col-filter--name', container) as HTMLInputElement | null;
  const nameQuery = nameInput ? nameInput.value : '';
  const filters = parseFilters(container);

  $$('tbody tr.t-file', table).forEach(row => {
    const htmlRow = row as HTMLElement;
    let visible = true;

    if (nameQuery) {
      const name = (row.children[0].textContent || '').toLowerCase();
      if (!name.includes(nameQuery.toLowerCase())) visible = false;
    }

    if (visible) {
      for (const f of filters) {
        const covered = parseInt(htmlRow.dataset[f.attrs.covered] || '0', 10) || 0;
        const total = parseInt(htmlRow.dataset[f.attrs.total] || '0', 10) || 0;
        const pct = total > 0 ? (covered * 100.0) / total : 100;
        if (!compare(f.op, pct, f.threshold)) { visible = false; break; }
      }
    }

    htmlRow.style.display = visible ? '' : 'none';
  });

  invalidateFileRowCache();
  updateTotalsRow(container);
  scheduleEqualizeBarWidths();
}

function updateFilterOptions(input: HTMLInputElement): void {
  const val = parseFloat(input.value);
  const wrapper = input.closest('.col-filter__coverage');
  const select = wrapper ? wrapper.querySelector('.col-filter__op') as HTMLSelectElement | null : null;
  if (!select) return;
  const gtOpt = select.querySelector('option[value="gt"]') as HTMLOptionElement | null;
  const ltOpt = select.querySelector('option[value="lt"]') as HTMLOptionElement | null;
  if (gtOpt) gtOpt.disabled = val >= 100;
  if (ltOpt) ltOpt.disabled = val <= 0;
  if (select.selectedOptions[0] && select.selectedOptions[0].disabled) {
    const first = select.querySelector('option:not(:disabled)') as HTMLOptionElement | null;
    if (first) select.value = first.value;
  }
}

function updateTotalsRow(container: Element): void {
  const rows = $$('tbody tr.t-file', container)
    .filter(r => (r as HTMLElement).style.display !== 'none');

  function sumData(attr: string): number {
    let total = 0;
    rows.forEach(r => { total += parseInt((r as HTMLElement).dataset[attr] || '0', 10) || 0; });
    return total;
  }

  const fileCount = $('.t-file-count', container);
  const totalFiles = parseInt(container.getAttribute('data-total-files') || '0', 10);
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
    if (covCell) { covCell.innerHTML = ''; covCell.className = covCell.className.replace(/green|yellow|red/g, '').trim(); }
    if (numEl) numEl.textContent = '';
    if (denEl) denEl.textContent = '';
    return;
  }
  const p = (covered * 100.0) / total;
  const cls = pctClass(p);
  if (covCell) {
    covCell.innerHTML = `<div class="coverage-cell">${renderCoverageBar(p)}<span class="coverage-pct">${p.toFixed(2)}%</span></div>`;
    covCell.className = `${covCell.className.replace(/green|yellow|red/g, '').trim()} ${cls}`;
  }
  if (numEl) numEl.textContent = fmtNum(covered) + '/';
  if (denEl) denEl.textContent = fmtNum(total);
}

// --- Source file rendering (on demand) -------------------------

function materializeSourceFile(sourceFileId: string): HTMLElement | null {
  const existing = document.getElementById(sourceFileId);
  if (existing) return existing;

  const idMap = (window as any)._simplecovIdMap as Record<string, string>;
  const coverage = (window as any)._simplecovFiles as Record<string, FileCoverage>;
  const branchCov = (window as any)._simplecovBranchCoverage as boolean;
  const methodCov = (window as any)._simplecovMethodCoverage as boolean;

  const targetFilename = idMap[sourceFileId];
  if (!targetFilename) return null;

  const html = renderSourceFile(targetFilename, coverage[targetFilename], branchCov, methodCov);
  const container = document.querySelector('.source_files')!;
  const wrapper = document.createElement('div');
  wrapper.innerHTML = html;
  const el = wrapper.firstElementChild as HTMLElement;
  container.appendChild(el);

  $$('pre code', el).forEach(e => { hljs.highlightElement(e as HTMLElement); });
  return el;
}

// --- Bar width equalization ------------------------------------

function setBarSizerWidth(sizers: Element[], px: number): void {
  const w = px + 'px';
  sizers.forEach(s => {
    const st = (s as HTMLElement).style;
    st.width = w; st.minWidth = w; st.maxWidth = w;
  });
}

function equalizeBarWidths(): void {
  $$('.file_list_container').forEach(container => {
    if ((container as HTMLElement).style.display === 'none') return;
    if ((container as HTMLElement).offsetWidth === 0) return;

    const table = $('table.file_list', container) as HTMLTableElement | null;
    if (!table) return;
    const sizers = $$('.bar-sizer', table);
    if (sizers.length === 0) return;

    const wrapper = table.closest('.file_list--responsive') as HTMLElement | null;
    if (!wrapper) return;

    wrapper.style.visibility = 'hidden';

    let lo = MIN_BAR_WIDTH, hi = MAX_BAR_WIDTH;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      setBarSizerWidth(sizers, mid);
      void table.offsetWidth;
      if (table.scrollWidth <= wrapper.clientWidth) lo = mid;
      else hi = mid - 1;
    }
    setBarSizerWidth(sizers, lo);

    wrapper.style.visibility = '';
  });
}

let equalizeRafId = 0;

function scheduleEqualizeBarWidths(): void {
  if (equalizeRafId) return;
  equalizeRafId = requestAnimationFrame(() => {
    equalizeRafId = 0;
    equalizeBarWidths();
  });
}

// --- Keyboard navigation ----------------------------------------

let focusedRow: HTMLElement | null = null;
let cachedFileRows: HTMLElement[] | null = null;

function invalidateFileRowCache(): void {
  cachedFileRows = null;
}

function getVisibleFileRows(): HTMLElement[] {
  if (cachedFileRows) return cachedFileRows;
  const visible = $$('.file_list_container').filter(c => (c as HTMLElement).style.display !== 'none');
  if (!visible.length) return [];
  cachedFileRows = $$('tbody tr.t-file', visible[0]).filter(r => (r as HTMLElement).style.display !== 'none') as HTMLElement[];
  return cachedFileRows;
}

function setFocusedRow(row: HTMLElement | null): void {
  if (focusedRow) focusedRow.classList.remove('keyboard-focus');
  focusedRow = row;
  if (focusedRow) {
    focusedRow.classList.add('keyboard-focus');
    focusedRow.scrollIntoView({ block: 'nearest' });
  }
}

function moveFocus(direction: 1 | -1): void {
  const rows = getVisibleFileRows();
  if (!rows.length) return;
  if (!focusedRow || rows.indexOf(focusedRow) === -1) {
    setFocusedRow(direction === 1 ? rows[0] : rows[rows.length - 1]);
    return;
  }
  const idx = rows.indexOf(focusedRow) + direction;
  if (idx >= 0 && idx < rows.length) setFocusedRow(rows[idx]);
}

function openFocusedRow(): void {
  if (!focusedRow) return;
  const link = focusedRow.querySelector('a.src_link');
  if (link) window.location.hash = link.getAttribute('href')!.substring(1);
}

function getMissedLines(): HTMLElement[] {
  return $$('.source-dialog .source_table li.missed, .source-dialog .source_table li.missed-branch, .source-dialog .source_table li.missed-method') as HTMLElement[];
}

function jumpToMissedLine(direction: 1 | -1): void {
  const lines = getMissedLines();
  if (!lines.length) return;

  const scrollTop = dialogBody.scrollTop;
  const midpoint = scrollTop + dialogBody.clientHeight / 2;

  if (direction === 1) {
    const next = lines.find(li => li.offsetTop > midpoint);
    const target = next || lines[0];
    dialogBody.scrollTop = target.offsetTop - dialogBody.clientHeight / 3;
  } else {
    let prev: HTMLElement | null = null;
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].offsetTop < midpoint - 10) { prev = lines[i]; break; }
    }
    const target = prev || lines[lines.length - 1];
    dialogBody.scrollTop = target.offsetTop - dialogBody.clientHeight / 3;
  }
}

// --- Source file dialog ----------------------------------------

let dialog: HTMLDialogElement;
let dialogBody: HTMLElement;
let dialogTitle: HTMLElement;
let activeSourceEl: HTMLElement | null = null;
let savedHeaderHTML = '';

function restoreActiveSource(): void {
  if (!activeSourceEl) return;
  if (savedHeaderHTML) {
    activeSourceEl.insertAdjacentHTML('afterbegin', savedHeaderHTML);
    savedHeaderHTML = '';
  }
  const container = document.querySelector('.source_files');
  if (container) container.appendChild(activeSourceEl);
  activeSourceEl = null;
}

function openSourceFile(sourceFileId: string, linenumber?: string): void {
  restoreActiveSource();

  const el = materializeSourceFile(sourceFileId);
  if (!el) return;

  const header = el.querySelector('.header');
  if (header) {
    savedHeaderHTML = header.outerHTML;
    dialogTitle.innerHTML = header.innerHTML;
    header.remove();
  }

  activeSourceEl = el;
  dialogBody.appendChild(el);

  if (!dialog.open) dialog.showModal();
  document.documentElement.style.overflow = 'hidden';
  dialogBody.focus();

  if (linenumber) {
    const targetLine = dialogBody.querySelector('li[data-linenumber="' + linenumber + '"]') as HTMLElement | null;
    if (targetLine) dialogBody.scrollTop = targetLine.offsetTop;
  }
}

function showFileList(tabId: string): void {
  setFocusedRow(null);
  invalidateFileRowCache();

  if (dialog.open) {
    restoreActiveSource();
    dialog.close();
    dialogBody.innerHTML = '';
    dialogTitle.innerHTML = '';
    document.documentElement.style.overflow = '';
  }

  if (tabId) {
    const tab = document.querySelector('.group_tabs a.' + tabId);
    if (tab) {
      $$('.group_tabs li').forEach(li => li.classList.remove('active'));
      tab.parentElement!.classList.add('active');
      $$('.file_list_container').forEach(c => (c as HTMLElement).style.display = 'none');
      const target = document.getElementById(tabId);
      if (target) target.style.display = '';
    }
  }
  const wrapper = document.getElementById('wrapper');
  if (wrapper && !wrapper.classList.contains('hide')) {
    scheduleEqualizeBarWidths();
  }
}

function navigateToHash(): void {
  const hash = window.location.hash.substring(1);

  if (!hash) {
    const firstTab = document.querySelector('.group_tabs a');
    if (firstTab) showFileList(firstTab.getAttribute('href')!.replace('#', ''));
    return;
  }

  if (hash.charAt(0) === '_') {
    showFileList(hash.substring(1));
  } else {
    const parts = hash.split('-L');
    if (!document.querySelector('.group_tabs li.active')) {
      const first = document.querySelector('.group_tabs li');
      if (first) first.classList.add('active');
    }
    openSourceFile(parts[0], parts[1]);
  }
}

function navigateToActiveTab(): void {
  const activeLink = document.querySelector('.group_tabs li.active a');
  if (activeLink) {
    window.location.hash = activeLink.getAttribute('href')!.replace('#', '#_');
  }
}

// --- Dark mode ------------------------------------------------

function initDarkMode(): void {
  const toggle = document.getElementById('dark-mode-toggle');
  if (!toggle) return;

  const root = document.documentElement;

  function isDark(): boolean {
    return root.classList.contains('dark-mode') ||
      (!root.classList.contains('light-mode') &&
        window.matchMedia('(prefers-color-scheme: dark)').matches);
  }

  function updateLabel(): void {
    toggle!.textContent = isDark() ? '\u2600\uFE0F Light' : '\uD83C\uDF19 Dark';
  }

  updateLabel();

  toggle.addEventListener('click', () => {
    const switchToLight = isDark();
    root.classList.toggle('light-mode', switchToLight);
    root.classList.toggle('dark-mode', !switchToLight);
    localStorage.setItem('simplecov-dark-mode', switchToLight ? 'light' : 'dark');
    updateLabel();
  });

  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if (!localStorage.getItem('simplecov-dark-mode')) updateLabel();
  });
}

// --- Initialization -------------------------------------------

// Wait for coverage data to be available, then render
function init(): void {
  if (!window.SIMPLECOV_DATA) {
    // Data not loaded yet - the coverage_data.js script tag is at the end of body,
    // so if DOMContentLoaded fires first, wait for it
    window.addEventListener('load', init);
    return;
  }

  const data = window.SIMPLECOV_DATA;

  // Show loading indicator
  const loadingEl = document.getElementById('loading');
  if (loadingEl) loadingEl.style.display = '';

  // Render all content from data
  renderPage(data);

  // Timeago — schedule the next update for exactly when the text would change
  function scheduleTimeago(): void {
    let minDelay = Infinity;
    $$('abbr.timeago').forEach(el => {
      const date = new Date(el.getAttribute('title') || '');
      if (isNaN(date.getTime())) return;
      el.textContent = timeago(date);
      minDelay = Math.min(minDelay, timeagoNextTick(date));
    });
    if (minDelay < Infinity) setTimeout(scheduleTimeago, minDelay);
  }
  scheduleTimeago();

  initDarkMode();

  // Table sorting
  function thToTdIndex(table: Element, clickedTh: Element): number {
    let idx = 0;
    for (const th of $$('thead tr:first-child th', table)) {
      const span = parseInt(th.getAttribute('colspan') || '1', 10);
      if (th === clickedTh) return idx + span - 1;
      idx += span;
    }
    return idx;
  }

  $$('table.file_list').forEach(table => {
    $$('thead tr:first-child th', table).forEach((th) => {
      th.classList.add('sorting');
      (th as HTMLElement).style.cursor = 'pointer';
      th.addEventListener('click', () => sortTable(table, thToTdIndex(table, th)));
    });
  });

  // Filter options init
  $$('.col-filter__value').forEach(el => updateFilterOptions(el as HTMLInputElement));

  // Prevent filter clicks from triggering sort
  $$('.col-filter--name, .col-filter__op, .col-filter__value, .col-filter__coverage').forEach(el => {
    el.addEventListener('click', e => e.stopPropagation());
  });

  // Filter change handlers
  on(document, 'input', '.col-filter--name, .col-filter__op, .col-filter__value', function () {
    if (this.classList.contains('col-filter__value')) updateFilterOptions(this as HTMLInputElement);
    filterTable(this.closest('.file_list_container')!);
  });
  on(document, 'change', '.col-filter__op, .col-filter__value', function () {
    if (this.classList.contains('col-filter__value')) updateFilterOptions(this as HTMLInputElement);
    filterTable(this.closest('.file_list_container')!);
  });

  // Keyboard shortcuts
  document.addEventListener('keydown', (e: KeyboardEvent) => {
    const inInput = (e.target as Element).matches('input, select, textarea');

    if (e.key === '/' && !inInput) {
      e.preventDefault();
      const visible = $$('.file_list_container').filter(c => (c as HTMLElement).style.display !== 'none');
      const input = visible.length ? $('.col-filter--name', visible[0]) as HTMLElement | null : null;
      if (input) input.focus();
      return;
    }

    if (e.key === 'Escape') {
      if (dialog.open) {
        e.preventDefault();
        navigateToActiveTab();
      } else if (inInput) {
        (e.target as HTMLElement).blur();
      } else if (focusedRow) {
        setFocusedRow(null);
      }
      return;
    }

    if (inInput) return;

    if (dialog.open) {
      if (e.key === 'n' && !e.shiftKey) { e.preventDefault(); jumpToMissedLine(1); }
      if (e.key === 'N' || (e.key === 'n' && e.shiftKey) || e.key === 'p') { e.preventDefault(); jumpToMissedLine(-1); }
      return;
    }

    if (e.key === 'j') { e.preventDefault(); moveFocus(1); }
    if (e.key === 'k') { e.preventDefault(); moveFocus(-1); }
    if (e.key === 'Enter' && focusedRow) { e.preventDefault(); openFocusedRow(); }
  });

  // Dialog setup
  dialog = document.getElementById('source-dialog') as HTMLDialogElement;
  dialogBody = document.getElementById('source-dialog-body')!;
  dialogTitle = document.getElementById('source-dialog-title')!;

  dialog.querySelector('.source-dialog__close')!.addEventListener('click', navigateToActiveTab);
  dialog.addEventListener('click', e => { if (e.target === dialog) navigateToActiveTab(); });

  // Event delegation for dynamic content
  on(document, 'click', '.t-missed-method-toggle', function (e: Event) {
    e.preventDefault();
    const parent = this.closest('.header') || this.closest('.source-dialog__title') || this.closest('.source-dialog__header');
    const list = parent ? parent.querySelector('.t-missed-method-list') as HTMLElement | null : null;
    if (list) list.style.display = list.style.display === 'none' ? '' : 'none';
  });

  on(document, 'click', 'a.src_link', function (e: Event) {
    e.preventDefault();
    window.location.hash = this.getAttribute('href')!.substring(1);
  });

  on(document, 'click', 'table.file_list tbody tr', function (e: Event) {
    if ((e.target as Element).closest('a')) return;
    const link = this.querySelector('a.src_link');
    if (link) window.location.hash = link.getAttribute('href')!.substring(1);
  });

  on(document, 'click', '.source-dialog .source_table li[data-linenumber]', function (e: Event) {
    e.preventDefault();
    dialogBody.scrollTop = (this as HTMLElement).offsetTop;
    const linenumber = (this as HTMLElement).dataset.linenumber;
    const sourceFileId = window.location.hash.substring(1).replace(/-L.*/, '');
    window.location.replace(window.location.href.replace(/#.*/, '#' + sourceFileId + '-L' + linenumber));
  });

  window.addEventListener('hashchange', navigateToHash);

  // Tab system
  $$('.file_list_container').forEach(c => (c as HTMLElement).style.display = 'none');

  $$('.file_list_container').forEach(container => {
    const id = container.id;
    const groupName = container.querySelector('.group_name');
    const coveredPct = container.querySelector('.covered_percent');

    const li = document.createElement('li');
    li.setAttribute('role', 'tab');
    const a = document.createElement('a');
    a.href = '#' + id;
    a.className = id;
    a.innerHTML = (groupName ? groupName.innerHTML : '') + ' (' + (coveredPct ? coveredPct.innerHTML : '') + ')';
    li.appendChild(a);
    document.querySelector('.group_tabs')!.appendChild(li);
  });

  on(document.querySelector('.group_tabs')!, 'click', 'a', function (e: Event) {
    e.preventDefault();
    window.location.hash = this.getAttribute('href')!.replace('#', '#_');
  });

  // Equalize bar column widths
  window.addEventListener('resize', scheduleEqualizeBarWidths);

  // Initial state
  navigateToHash();

  // Finalize loading
  if (loadingEl) {
    loadingEl.style.transition = 'opacity 0.3s';
    loadingEl.style.opacity = '0';
    setTimeout(() => { loadingEl.style.display = 'none'; }, 300);
  }

  const wrapperEl = document.getElementById('wrapper');
  if (wrapperEl) wrapperEl.classList.remove('hide');

  equalizeBarWidths();
}

document.addEventListener('DOMContentLoaded', init);
