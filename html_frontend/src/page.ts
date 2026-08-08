// Full-page assembly from the coverage data, plus the on-demand source-file
// materializer. Owns the render state that maps file ids back to coverage.

import hljs from 'highlight.js/lib/core';
import ruby from 'highlight.js/lib/languages/ruby';
import { $$, escapeHTML } from './dom';
import { pctClass, fileId, toHtmlId } from './format';
import { renderFileList } from './render_list';
import { renderSourceFile } from './render_source';
import type { CoverageData, FileCoverage } from './types';

hljs.registerLanguage('ruby', ruby);

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
  branchCoverage: boolean;
  methodCoverage: boolean;
}
let renderState: RenderState | null = null;

export function renderPage(data: CoverageData): void {
  const meta = data.meta;
  const branchCoverage = meta.branch_coverage;
  const methodCoverage = meta.method_coverage;

  // Page title and favicon
  document.title = `Code coverage for ${meta.project_name}`;
  const allFiles = Object.keys(data.coverage);
  const overallPct = data.total.lines.total > 0 ? data.total.lines.percent : 100.0;
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
      branchCoverage,
      methodCoverage
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
        branchCoverage,
        methodCoverage
      })
    );
  }
  content.innerHTML = fileListSections.join('');

  // Cache the lookup map and coverage data so the on-demand source file
  // materializer can resolve an id back to its FileCoverage in O(1).
  const idToFilename: Record<string, string> = {};
  for (const fn of allFiles) idToFilename[fileId(fn)] = fn;
  renderState = { idToFilename, coverage: data.coverage, branchCoverage, methodCoverage };

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

export function materializeSourceFile(sourceFileId: string): HTMLElement | null {
  const existing = document.getElementById(sourceFileId);
  if (existing) return existing;
  if (!renderState) return null;

  const targetFilename = renderState.idToFilename[sourceFileId];
  if (!targetFilename) return null;

  const html = renderSourceFile(
    targetFilename,
    renderState.coverage[targetFilename],
    renderState.branchCoverage,
    renderState.methodCoverage,
  );
  const container = document.querySelector('.source_files')!;
  const wrapper = document.createElement('div');
  wrapper.innerHTML = html;
  const el = wrapper.firstElementChild as HTMLElement;
  container.appendChild(el);

  $$('pre code', el).forEach((e) => hljs.highlightElement(e as HTMLElement));
  return el;
}
