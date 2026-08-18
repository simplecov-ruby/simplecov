// Full-page assembly: renderPage against the real index.html skeleton, the
// canvas-drawn favicon (canvas stubbed — happy-dom has no 2d context), and
// the on-demand source-file materializer with its highlight.js pass.
import { afterEach, beforeEach, describe, expect, mock, spyOn, test } from 'bun:test';
import { installPageSkeleton, coverageData } from './fixture';
import { renderPage, updateFavicon, materializeSourceFile, contextsForSourceLine } from '../src/page';
import { precomputeFileIds, fileId, toHtmlId } from '../src/format';
import type { CoverageData } from '../src/types';

function removeFaviconLink(): void {
  document.head.querySelector('link[rel="icon"]')?.remove();
}

async function boot(data: CoverageData): Promise<void> {
  await precomputeFileIds(Object.keys(data.coverage));
  renderPage(data);
}

beforeEach(() => {
  installPageSkeleton();
  document.body.removeAttribute('data-branch-coverage');
  removeFaviconLink();
});

afterEach(() => {
  mock.restore();
});

describe('materializeSourceFile before rendering', () => {
  test('returns null for an id no render has resolved', () => {
    expect(materializeSourceFile('deadbeef')).toBeNull();
  });
});

describe('updateFavicon', () => {
  test('is a no-op without a drawable canvas', () => {
    // happy-dom's canvas has no 2d context, so the guard bails before
    // creating a <link>.
    updateFavicon();
    expect(document.head.querySelector('link[rel="icon"]')).toBeNull();
  });

  test('draws a favicon in the coverage band colour once a context exists', async () => {
    const data = coverageData();
    await boot(data); // (5/7)*100 ≈ 71.43% → red band
    document.documentElement.style.setProperty('--red', '#ff0000');

    const fills: string[] = [];
    const fakeCtx = {
      fillStyle: '',
      fillRect(x: number, y: number, w: number, h: number) {
        fills.push(`${this.fillStyle}:${x},${y},${w},${h}`);
      }
    };
    const realCreateElement = document.createElement.bind(document);
    spyOn(document, 'createElement').mockImplementation(((tag: string) => {
      if (tag !== 'canvas') return realCreateElement(tag);
      return {
        width: 0,
        height: 0,
        getContext: () => fakeCtx,
        toDataURL: () => 'data:image/png;base64,AAAA'
      };
    }) as typeof document.createElement);

    updateFavicon();
    const link = document.head.querySelector('link[rel="icon"]') as HTMLLinkElement;
    expect(link.href).toBe('data:image/png;base64,AAAA');
    expect(fills).toEqual(['#ff0000:0,0,16,16']);

    // A second call reuses the existing <link> instead of adding another.
    updateFavicon();
    expect(document.head.querySelectorAll('link[rel="icon"]').length).toBe(1);

    // Without a resolvable band colour the guard leaves the link alone.
    document.documentElement.style.removeProperty('--red');
    link.href = 'data:previous';
    updateFavicon();
    expect(link.href).toBe('data:previous');
  });
});

describe('renderPage', () => {
  test('renders a line-coverage-only report', async () => {
    const data = coverageData();
    await boot(data);

    expect(document.title).toBe('Code coverage for Sample Project');
    expect(document.body.hasAttribute('data-branch-coverage')).toBe(false);

    const container = document.getElementById('g-total')!;
    expect(container.getAttribute('data-total-files')).toBe('2');
    expect(container.querySelectorAll('tbody tr.t-file').length).toBe(2);

    const footer = document.getElementById('footer')!;
    expect(footer.innerHTML).toContain('simplecov</a> v0.23.1');
    expect(footer.innerHTML).toContain('using RSpec');
    expect(footer.querySelector('abbr.timeago')).not.toBeNull();

    const sourceFooter = document.getElementById('source-dialog-footer')!;
    expect(sourceFooter.innerHTML).toBe(footer.innerHTML);

    const legend = document.getElementById('source-legend')!;
    expect(legend.textContent).toContain('Covered');
    expect(legend.textContent).toContain('Skipped');
    expect(legend.textContent).toContain('Missed line');
    expect(legend.textContent).not.toContain('Missed branch');
    expect(legend.textContent).not.toContain('Missed method');
    expect(legend.querySelectorAll('.source-legend__row')).toHaveLength(1);
    expect(legend.querySelector('.source-legend__row--line')!.textContent).toContain('Covered');
  });

  test('renders branch and method coverage with groups', async () => {
    const data = coverageData();
    data.meta.branch_coverage = true;
    data.meta.method_coverage = true;
    data.total.branches = {covered: 1, missed: 1, total: 2, percent: 50.0, strength: 1};
    data.total.methods = {covered: 1, missed: 1, total: 2, percent: 50.0, strength: 1};
    const missed = data.coverage['lib/missed.rb'];
    missed.branches = [
      {type: 'then', start_line: 2, end_line: 2, coverage: 0, inline: true, report_line: 2}
    ];
    missed.covered_branches = 0;
    missed.total_branches = 1;
    missed.methods = [{name: '#baz', start_line: 1, end_line: 4, coverage: 0}];
    missed.covered_methods = 0;
    missed.total_methods = 1;
    data.groups = {
      'Libs & Co': {
        files: ['lib/covered.rb', 'lib/gone.rb'],
        lines: {covered: 3, missed: 0, total: 3, percent: 100.0, strength: 1}
      }
    };

    await boot(data);

    expect(document.body.getAttribute('data-branch-coverage')).toBe('true');
    const groupContainer = document.getElementById(toHtmlId('group-Libs & Co'))!;
    // 'lib/gone.rb' has no coverage entry and is skipped.
    expect(groupContainer.querySelectorAll('tbody tr.t-file').length).toBe(1);

    const legend = document.getElementById('source-legend')!;
    expect(legend.textContent).toContain('Missed branch');
    expect(legend.textContent).toContain('Missed method');
    expect(legend.querySelectorAll('.source-legend__row')).toHaveLength(3);
    expect(legend.querySelector('.source-legend__row--branch')!.textContent).toContain('Missed branch');
    expect(legend.querySelector('.source-legend__row--method')!.textContent).toContain('Missed method');
  });

  test('falls back to a 100% favicon band when the primary stat is missing', async () => {
    const data = coverageData();
    data.total = {};
    await boot(data);
    expect(document.getElementById('g-total')).not.toBeNull();
  });
});

describe('materializeSourceFile', () => {
  test('materializes, highlights, and memoizes source views', async () => {
    const data = coverageData();
    await boot(data);

    const id = fileId('lib/covered.rb');
    const el = materializeSourceFile(id)!;
    expect(el.id).toBe(id);
    expect(el.parentElement).toBe(document.querySelector('.source_files'));
    expect(el.querySelectorAll('pre ol li').length).toBe(4);
    // highlight.js rewrote the Ruby source into token spans.
    expect(el.querySelector('pre code.ruby')!.innerHTML).toContain('hljs-');

    // Second lookup returns the already-materialized element.
    expect(materializeSourceFile(id)).toBe(el);

    // Unknown ids resolve to nothing.
    expect(materializeSourceFile('ffffffff')).toBeNull();
  });
});

describe('renderPage with recorded contexts', () => {
  function withContexts() {
    const data = coverageData();
    data.contexts = ['spec/covered_spec.rb:4'];
    data.coverage['lib/covered.rb'].contexts = { '0': '2' }; // line 2 only
    return data;
  }

  test('adds the drained legend row exactly when contexts are recorded', async () => {
    await boot(coverageData());
    expect(document.getElementById('source-legend')!.textContent).not.toContain('Covered outside tests');

    installPageSkeleton();
    await boot(withContexts());
    const legend = document.getElementById('source-legend')!;
    expect(legend.textContent).toContain('Covered outside tests');
    expect(legend.querySelector('.source-legend__swatch--outside-tests')).not.toBeNull();
  });

  test('threads contexts into materialized source files', async () => {
    await boot(withContexts());
    const el = materializeSourceFile(fileId('lib/covered.rb'))!;

    // Line 2 carries its test badge; lines 1 and 4 are covered by nothing.
    expect(el.querySelector('button.hits--tests[data-tests-line="2"]')!.getAttribute('data-content')).toBe('1 test');
    expect(Array.from(el.querySelectorAll('li.outside-tests')).map((li) => li.getAttribute('data-linenumber')))
      .toEqual(['1', '4']);
  });

  test('resolves a line\'s covering ids for the peek, and null off the map', async () => {
    await boot(withContexts());
    expect(contextsForSourceLine(fileId('lib/covered.rb'), 2)).toEqual(['spec/covered_spec.rb:4']);
    expect(contextsForSourceLine(fileId('lib/covered.rb'), 1)).toEqual([]);
    expect(contextsForSourceLine('nope', 1)).toBeNull();
  });

  test('resolves nothing when the report recorded no contexts', async () => {
    await boot(coverageData());
    expect(contextsForSourceLine(fileId('lib/covered.rb'), 2)).toBeNull();
  });
});
