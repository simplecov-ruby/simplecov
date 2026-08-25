// Full-page assembly from the coverage data, plus the on-demand source-file
// materializer. Owns the render state that maps file ids back to coverage.

import hljs from 'highlight.js/lib/core';
import ruby from 'highlight.js/lib/languages/ruby';
import haml from 'highlight.js/lib/languages/haml';
import erb from './erb';
import slim from './slim';
import { $$, escapeHTML } from './dom';
import { pctClass, fileId, toHtmlId } from './format';
import { activeCoverageType, primaryCoverageStat } from './coverage';
import { renderFileList } from './render_list';
import { renderSourceFile } from './render_source';
import { decodeFileContexts, contextIdsForLine, type FileContextIndex } from './contexts';
import type { CoverageData, FileCoverage } from './types';

hljs.registerLanguage('ruby', ruby);
// A `.erb` view is markup with Ruby inside it, so it gets its own grammar
// rather than being fed to the Ruby one, which declines to match markup and
// leaves the whole file unhighlighted. Registered by name because that is how
// highlight.js resolves the sub-language `erb` delegates its tags to.
hljs.registerLanguage('erb', erb);
hljs.registerLanguage('haml', haml);
hljs.registerLanguage('slim', slim);

// The favicon is a solid square in the coverage band's colour, drawn at
// render time from the live palette so it matches the active theme.
// Reading the band's custom property (--green/--red/--yellow, which the
// asset build exempts from mangling) keeps it in lockstep with the
// stylesheet in both themes; controls.ts calls updateFavicon() again
// whenever the theme changes.
let faviconBand: string | null = null;

export function updateFavicon(): void {
  if (!faviconBand) return;
  const color = getComputedStyle(document.documentElement).getPropertyValue(`--${faviconBand}`).trim();
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 16;
  const ctx = canvas.getContext('2d');
  if (!color || !ctx) return;
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 16, 16);

  let link = document.querySelector('link[rel="icon"]') as HTMLLinkElement | null;
  if (!link) {
    link = document.createElement('link');
    link.rel = 'icon';
    link.type = 'image/png';
    document.head.appendChild(link);
  }
  link.href = canvas.toDataURL('image/png');
}

// Module-level state populated by renderPage() and consumed by the
// on-demand source-file materializer. Holding it here (typed) avoids
// hanging caches off the global Window object.
interface RenderState {
  idToFilename: Record<string, string>;
  coverage: Record<string, FileCoverage>;
  lineCoverage: boolean;
  branchCoverage: boolean;
  methodCoverage: boolean;
  // The recorded context ids, or null for a report without recordings.
  contexts: string[] | null;
}
let renderState: RenderState | null = null;

// Per-file decoded context indices, built on first use: only opened files
// pay the decode, and each pays it once.
const contextIndexCache = new Map<string, FileContextIndex>();

// How many run names the footer reads aloud before folding the full
// list behind a disclosure. A merged CI matrix can carry hundreds of
// distinct names, and enumerating them once filled the whole viewport
// before the report content began (#1284).
const FOOTER_RUN_LIMIT = 3;

function runNamesHtml(meta: CoverageData['meta']): string {
  // Older documents carry only the joined command_name; a run name can
  // itself contain a comma, so the joined string is never split back
  // apart into a count.
  const names = meta.command_names && meta.command_names.length ? meta.command_names : [meta.command_name];
  if (names.length <= FOOTER_RUN_LIMIT) return escapeHTML(names.join(', '));
  return `<details class="footer-runs"><summary>${escapeHTML(names[0])} and ${names.length - 1} other runs</summary>` +
    `<span class="footer-runs__list">${escapeHTML(names.join(', '))}</span></details>`;
}

export function renderPage(data: CoverageData): void {
  const meta = data.meta;
  const lineCoverage = meta.line_coverage;
  const branchCoverage = meta.branch_coverage;
  const methodCoverage = meta.method_coverage;
  const primaryCoverage = activeCoverageType(meta);

  // Page title and favicon
  document.title = `Code coverage for ${meta.project_name}`;
  const allFiles = Object.keys(data.coverage);
  const overall = primaryCoverageStat(data.total, primaryCoverage);
  const overallPct = overall && overall.total > 0 ? overall.percent : 100.0;
  faviconBand = pctClass(overallPct);
  updateFavicon();

  if (branchCoverage) document.body.setAttribute('data-branch-coverage', 'true');

  // Content: file lists. Building the full markup in memory and assigning
  // innerHTML once avoids the O(n^2) re-parse that `innerHTML += ...` in a
  // loop would trigger on reports with many groups.
  const content = document.getElementById('content')!;
  const fileListSections = [
    renderFileList({
      containerId: 'g-total',
      title: 'All Files',
      filenames: allFiles,
      stats: data.total,
      allCoverage: data.coverage,
      lineCoverage,
      branchCoverage,
      methodCoverage,
      primaryCoverage,
      contextsEnabled: !!data.contexts
    }),
  ];
  for (const groupName of Object.keys(data.groups)) {
    const group = data.groups[groupName];
    fileListSections.push(
      renderFileList({
        containerId: toHtmlId(`group-${groupName}`),
        title: groupName,
        filenames: group.files || [],
        stats: group,
        allCoverage: data.coverage,
        lineCoverage,
        branchCoverage,
        methodCoverage,
        primaryCoverage,
        contextsEnabled: !!data.contexts
      })
    );
  }
  content.innerHTML = fileListSections.join('');

  // Cache the lookup map and coverage data so the on-demand source file
  // materializer can resolve an id back to its FileCoverage in O(1).
  const idToFilename: Record<string, string> = {};
  for (const fn of allFiles) idToFilename[fileId(fn)] = fn;
  renderState = {
    idToFilename, coverage: data.coverage, lineCoverage, branchCoverage, methodCoverage,
    contexts: data.contexts || null
  };
  contextIndexCache.clear();

  // Footer
  const timestamp = new Date(meta.timestamp);
  const footerHtml = `Generated <abbr class="timeago" title="${timestamp.toISOString()}">${timestamp.toISOString()}</abbr>` +
    ` by <a href="https://github.com/simplecov-ruby/simplecov">simplecov</a> v${escapeHTML(meta.simplecov_version)}` +
    ` using ${runNamesHtml(meta)}`;
  document.getElementById('footer')!.innerHTML = footerHtml;
  document.getElementById('source-dialog-footer')!.innerHTML = footerHtml;

  // Source legend
  const legend = document.getElementById('source-legend')!;
  let legendHtml = '';
  // A tracked report splits the covered chip in two, renaming green to say
  // what it then actually means and pairing it with the slate chip for
  // coverage no recorded test produced.
  if (lineCoverage) {
    const coveredChips = data.contexts
      ? '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--covered"></span>Covered by tests</span>' +
        '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--outside-tests"></span>Covered outside tests</span>'
      : '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--covered"></span>Covered</span>';
    legendHtml += '<div class="source-legend__row source-legend__row--line">' +
      coveredChips +
      '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--skipped"></span>Skipped</span>' +
      '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--missed"></span>Missed line</span>' +
      '</div>';
  }
  if (branchCoverage) {
    legendHtml += '<div class="source-legend__row source-legend__row--branch">' +
      '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--missed-branch"></span>Missed branch</span>' +
      '</div>';
  }
  if (methodCoverage) {
    legendHtml += '<div class="source-legend__row source-legend__row--method">' +
      '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--missed-method"></span>Missed method</span>' +
      '</div>';
  }
  legend.innerHTML = legendHtml;
}

export function materializeSourceFile(sourceFileId: string): HTMLElement | null {
  const existing = document.getElementById(sourceFileId);
  if (existing) return existing;
  if (!renderState) return null;

  const targetFilename = renderState.idToFilename[sourceFileId];
  if (!targetFilename) return null;

  const html = renderSourceFile(
    targetFilename,
    renderState.coverage[targetFilename],
    renderState.lineCoverage,
    renderState.branchCoverage,
    renderState.methodCoverage,
    renderState.contexts || undefined,
  );
  const container = document.querySelector('.source_files')!;
  const wrapper = document.createElement('div');
  wrapper.innerHTML = html;
  const el = wrapper.firstElementChild as HTMLElement;
  container.appendChild(el);

  $$('pre code', el).forEach((e) => hljs.highlightElement(e as HTMLElement));
  return el;
}

// The covering test ids for one line of a materialized source file, or
// null when the report carries no recordings (or the id is unknown). This
// is the peek panel's resolver; the ids come back sorted, matching the
// CLI's answer for the same file and line.
export function contextsForSourceLine(sourceFileId: string, line: number): string[] | null {
  if (!renderState || !renderState.contexts) return null;
  const filename = renderState.idToFilename[sourceFileId];
  if (!filename) return null;

  let index = contextIndexCache.get(sourceFileId);
  if (!index) {
    const file = renderState.coverage[filename];
    index = decodeFileContexts(file.contexts, file.source.length);
    contextIndexCache.set(sourceFileId, index);
  }
  return contextIdsForLine(index, renderState.contexts, line);
}
