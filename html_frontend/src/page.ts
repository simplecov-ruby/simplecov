
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
import type { CoverageData, FileCoverage, ProductionData } from './types';

hljs.registerLanguage('ruby', ruby);
hljs.registerLanguage('erb', erb);
hljs.registerLanguage('haml', haml);
hljs.registerLanguage('slim', slim);

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

interface RenderState {
  idToFilename: Record<string, string>;
  coverage: Record<string, FileCoverage>;
  lineCoverage: boolean;
  branchCoverage: boolean;
  methodCoverage: boolean;
  contexts: string[] | null;
  production: ProductionData | null;
}
let renderState: RenderState | null = null;

const contextIndexCache = new Map<string, FileContextIndex>();

const FOOTER_RUN_LIMIT = 3;

function runNamesHtml(meta: CoverageData['meta']): string {
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

  document.title = `Code coverage for ${meta.project_name}`;
  const allFiles = Object.keys(data.coverage);
  const overall = primaryCoverageStat(data.total, primaryCoverage);
  const overallPct = overall && overall.total > 0 ? overall.percent : 100.0;
  faviconBand = pctClass(overallPct);
  updateFavicon();

  if (branchCoverage) document.body.setAttribute('data-branch-coverage', 'true');

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
      contextsEnabled: !!data.contexts,
      production: data.production
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
        contextsEnabled: !!data.contexts,
        production: data.production
      })
    );
  }
  content.innerHTML = fileListSections.join('');

  const idToFilename: Record<string, string> = {};
  for (const fn of allFiles) idToFilename[fileId(fn)] = fn;
  renderState = {
    idToFilename, coverage: data.coverage, lineCoverage, branchCoverage, methodCoverage,
    contexts: data.contexts || null,
    production: data.production || null
  };
  contextIndexCache.clear();

  const timestamp = new Date(meta.timestamp);
  const footerHtml = `Generated <abbr class="timeago" title="${timestamp.toISOString()}">${timestamp.toISOString()}</abbr>` +
    ` by <a href="https://github.com/simplecov-ruby/simplecov">simplecov</a> v${escapeHTML(meta.simplecov_version)}` +
    ` using ${runNamesHtml(meta)}`;
  document.getElementById('footer')!.innerHTML = footerHtml;
  document.getElementById('source-dialog-footer')!.innerHTML = footerHtml;

  const legend = document.getElementById('source-legend')!;
  let legendHtml = '';
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
  if (data.production && lineCoverage) {
    legendHtml += '<div class="source-legend__row source-legend__row--production">' +
      '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--production-never"></span>Never ran in production</span>' +
      '<span class="source-legend__item"><span class="source-legend__swatch source-legend__swatch--production-ran"></span>Untested, runs in production</span>' +
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
    renderState.production ? (renderState.production.files[targetFilename] || null) : undefined,
  );
  const container = document.querySelector('.source_files')!;
  const wrapper = document.createElement('div');
  wrapper.innerHTML = html;
  const el = wrapper.firstElementChild as HTMLElement;
  container.appendChild(el);

  $$('pre code', el).forEach((e) => hljs.highlightElement(e as HTMLElement));
  return el;
}

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
