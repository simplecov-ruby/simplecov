import type { CoverageData } from '../src/types';

export const PAGE_BODY_HTML = `
    <div id="loading" style="display: none">
      <div id="loading-inner">
        <div id="loading-bar-track">
          <div id="loading-bar-fill"></div>
        </div>
        <div id="loading-text">Loading...</div>
      </div>
    </div>

    <div id="wrapper" class="hide">
      <div class="tab-bar">
        <ul class="group_tabs" role="tablist"></ul>
        <div class="toolbar">
          <button class="toolbar-toggle" type="button" data-toggle="colorblind" aria-pressed="false" title="Use a colorblind-friendly palette and coverage symbols">🎨 Colorblind</button>
          <button class="toolbar-toggle" type="button" data-toggle="dark"></button>
        </div>
      </div>

      <div id="content"></div>

      <div id="footer"></div>

      <div class="source_files" style="display:none"></div>
    </div>

    <dialog id="source-dialog" class="source-dialog">
      <div class="source-dialog__header">
        <div class="source-dialog__title" id="source-dialog-title"></div>
        <div class="source-legend" id="source-legend"></div>
        <div class="source-dialog__toggles">
          <button class="toolbar-toggle" type="button" data-toggle="colorblind" aria-pressed="false" title="Use a colorblind-friendly palette and coverage symbols">🎨 Colorblind</button>
          <button class="toolbar-toggle" type="button" data-toggle="dark"></button>
        </div>
        <button class="source-dialog__close" aria-label="Close" title="Close">&times;</button>
      </div>
      <div class="source-dialog__body" id="source-dialog-body" tabindex="0"></div>
      <div class="source-dialog__footer" id="source-dialog-footer"></div>
    </dialog>
`;

export function installPageSkeleton(): void {
  document.documentElement.className = '';
  document.body.innerHTML = PAGE_BODY_HTML;
}

export function coverageData(): CoverageData {
  return {
    meta: {
      simplecov_version: '0.23.1',
      command_name: 'RSpec',
      project_name: 'Sample Project',
      timestamp: '2026-08-11T00:00:00+00:00',
      root: '/project',
      line_coverage: true,
      branch_coverage: false,
      method_coverage: false
    },
    total: {
      lines: {covered: 5, missed: 2, total: 7, percent: (5 / 7) * 100, strength: 1}
    },
    coverage: {
      'lib/covered.rb': {
        lines: [1, 2, null, 1],
        source: ['def foo', '  :bar', 'end', ''],
        lines_covered_percent: 100.0,
        covered_lines: 3,
        missed_lines: 0,
        total_lines: 3
      },
      'lib/missed.rb': {
        lines: [1, 0, 0, null, 1],
        source: ['def baz', '  if q', '    :qux', 'end', ''],
        lines_covered_percent: 50.0,
        covered_lines: 2,
        missed_lines: 2,
        total_lines: 4
      }
    },
    groups: {}
  };
}
