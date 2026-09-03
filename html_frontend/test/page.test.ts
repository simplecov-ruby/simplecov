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

function fakeCanvas(): string[] {
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
      getContext: (kind: string) => (kind === '2d' ? fakeCtx : null),
      toDataURL: (type: string) => `data:${type};base64,AAAA`
    };
  }) as typeof document.createElement);
  return fills;
}

function setBandColours(): void {
  document.documentElement.style.setProperty('--red', '#ff0000');
  document.documentElement.style.setProperty('--yellow', '#ffff00');
  document.documentElement.style.setProperty('--green', '#00ff00');
}

function clearBandColours(): void {
  for (const band of ['--red', '--yellow', '--green']) document.documentElement.style.removeProperty(band);
}

function textNodeCount(el: Element): number {
  return el.childNodes.length - el.children.length;
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
    updateFavicon();
    expect(document.head.querySelector('link[rel="icon"]')).toBeNull();
  });

  test('draws a favicon in the coverage band colour once a context exists', async () => {
    const data = coverageData();
    await boot(data);
    document.documentElement.style.setProperty('--red', ' #ff0000 ');

    const fills = fakeCanvas();

    updateFavicon();
    const link = document.head.querySelector('link[rel="icon"]') as HTMLLinkElement;
    expect(link.href).toBe('data:image/png;base64,AAAA');
    expect(link.type).toBe('image/png');
    expect(fills).toEqual(['#ff0000:0,0,16,16']);

    updateFavicon();
    expect(document.head.querySelectorAll('link[rel="icon"]').length).toBe(1);

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
    expect(legend.children).toHaveLength(1);
    expect(textNodeCount(legend)).toBe(0);
    const lineRow = legend.querySelector('.source-legend__row--line')!;
    expect(lineRow.textContent).toContain('Covered');
    expect(textNodeCount(lineRow)).toBe(0);
    expect(lineRow.querySelector('.source-legend__swatch--covered')).not.toBeNull();
    expect(lineRow.querySelector('.source-legend__swatch--skipped')).not.toBeNull();
    expect(lineRow.querySelector('.source-legend__swatch--missed')).not.toBeNull();
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
    expect(groupContainer.querySelectorAll('tbody tr.t-file').length).toBe(1);

    const legend = document.getElementById('source-legend')!;
    expect(legend.textContent).toContain('Missed branch');
    expect(legend.textContent).toContain('Missed method');
    expect(legend.querySelectorAll('.source-legend__row')).toHaveLength(3);
    expect(legend.children).toHaveLength(3);
    expect(textNodeCount(legend)).toBe(0);
    expect(legend.querySelector('.source-legend__row--branch')!.textContent).toContain('Missed branch');
    expect(legend.querySelector('.source-legend__row--branch .source-legend__swatch--missed-branch')).not.toBeNull();
    expect(legend.querySelector('.source-legend__row--method')!.textContent).toContain('Missed method');
    expect(legend.querySelector('.source-legend__row--method .source-legend__swatch--missed-method')).not.toBeNull();

    const groupRows = groupContainer.querySelectorAll('tr.t-file[data-covered-outside-lines]');
    expect(groupRows).toHaveLength(0);
  });

  test('falls back to a 100% favicon band when the primary stat is missing', async () => {
    const data = coverageData();
    data.total = {};
    await boot(data);
    expect(document.getElementById('g-total')).not.toBeNull();
  });

  test('draws the favicon during render in the band of the overall percentage', async () => {
    setBandColours();
    const fills = fakeCanvas();
    await boot(coverageData());
    expect(fills).toEqual(['#ff0000:0,0,16,16']);
    expect(document.head.querySelector('link[rel="icon"]')).not.toBeNull();
    clearBandColours();
  });

  test('treats a report with nothing to cover as fully covered for the favicon', async () => {
    setBandColours();
    const fills = fakeCanvas();
    const data = coverageData();
    data.total.lines = {covered: 0, missed: 0, total: 0, percent: 0, strength: 0};
    await boot(data);
    expect(fills).toEqual(['#00ff00:0,0,16,16']);
    clearBandColours();
  });

  test('names the all-files list and keeps the sections free of stray text', async () => {
    const data = coverageData();
    data.groups = {Libraries: {files: ['lib/covered.rb'], lines: {covered: 3, missed: 0, total: 3, percent: 100, strength: 1}}};
    await boot(data);
    expect(document.querySelector('#g-total .group_name')!.textContent).toBe('All Files');
    const content = document.getElementById('content')!;
    expect(content.children).toHaveLength(2);
    expect(textNodeCount(content)).toBe(0);
  });

  test('renders an empty list for a group without files', async () => {
    const data = coverageData();
    data.groups = {Empty: {lines: {covered: 0, missed: 0, total: 0, percent: 100, strength: 0}}};
    await boot(data);
    const group = document.getElementById(toHtmlId('group-Empty'))!;
    expect(group.querySelectorAll('tbody tr.t-file')).toHaveLength(0);
    expect(group.getAttribute('data-total-files')).toBe('0');
  });

  test('attributes lines to tests only when the report recorded contexts', async () => {
    const data = coverageData();
    data.groups = {Libraries: {files: ['lib/covered.rb'], lines: {covered: 3, missed: 0, total: 3, percent: 100, strength: 1}}};
    await boot(data);
    expect(document.querySelector('#g-total tr.t-file[data-covered-outside-lines]')).toBeNull();
    expect(document.querySelector(`#${toHtmlId('group-Libraries')} tr.t-file[data-covered-outside-lines]`)).toBeNull();

    installPageSkeleton();
    data.contexts = ['spec/covered_spec.rb:4'];
    await boot(data);
    expect(document.querySelectorAll('#g-total tr.t-file[data-covered-outside-lines]')).toHaveLength(2);
    expect(document.querySelectorAll(`#${toHtmlId('group-Libraries')} tr.t-file[data-covered-outside-lines]`)).toHaveLength(1);
  });

  test('omits the line legend row when line coverage is off', async () => {
    const data = coverageData();
    data.meta.line_coverage = false;
    data.meta.branch_coverage = true;
    data.total.branches = {covered: 1, missed: 1, total: 2, percent: 50.0, strength: 1};
    await boot(data);
    const legend = document.getElementById('source-legend')!;
    expect(legend.querySelector('.source-legend__row--line')).toBeNull();
    expect(legend.children).toHaveLength(1);
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
    expect(el.querySelector('pre code.ruby')!.innerHTML).toContain('hljs-');

    expect(materializeSourceFile(id)).toBe(el);

    expect(materializeSourceFile('ffffffff')).toBeNull();
  });

  test('highlights a template as markup with Ruby inside it', async () => {
    const template = 'app/views/foos/show.html.erb';
    const data = coverageData();
    data.coverage[template] = {
      lines: [1, 1],
      source: ['<h1 class="title">Foo</h1>', '<%= @foo.bar %>'],
      lines_covered_percent: 100.0,
      covered_lines: 2,
      missed_lines: 0,
      total_lines: 2
    };
    await boot(data);

    const code = materializeSourceFile(fileId(template))!.querySelectorAll('pre code.erb');
    expect(code[0].innerHTML).toContain('hljs-name');
    expect(code[1].innerHTML).toContain('language-ruby');
  });

  test.each([
    ['app/views/foos/show.html.haml', ['%h1= @foo.bar', '- if @admin'], 'haml'],
    ['app/views/foos/show.html.slim', ['h1 = @foo.bar', '- if @admin'], 'slim']
  ])('highlights %s with its own grammar', async (template, source, language) => {
    const data = coverageData();
    data.coverage[template] = {
      lines: [1, 1],
      source,
      lines_covered_percent: 100.0,
      covered_lines: 2,
      missed_lines: 0,
      total_lines: 2
    };
    await boot(data);

    const code = materializeSourceFile(fileId(template))!.querySelectorAll(`pre code.${language}`);
    expect(code).toHaveLength(2);
    expect(code[1].innerHTML).toContain('language-ruby');
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
    const untracked = document.getElementById('source-legend')!;
    expect(untracked.textContent).not.toContain('Covered outside tests');
    expect(untracked.textContent).not.toContain('Covered by tests');

    installPageSkeleton();
    await boot(withContexts());
    const legend = document.getElementById('source-legend')!;
    expect(legend.textContent).toContain('Covered outside tests');
    expect(legend.querySelector('.source-legend__swatch--outside-tests')).not.toBeNull();
  });

  test('splits the covered chip by test attribution inside the line row', async () => {
    await boot(withContexts());
    const legend = document.getElementById('source-legend')!;

    expect(legend.querySelector('.source-legend__row--tests')).toBeNull();
    const lineRow = legend.querySelector('.source-legend__row--line')!;
    const labels = Array.from(lineRow.querySelectorAll('.source-legend__item'), (item) => item.textContent);
    expect(labels).toEqual(['Covered by tests', 'Covered outside tests', 'Skipped', 'Missed line']);
    expect(lineRow.querySelector('.source-legend__swatch--covered')).not.toBeNull();
    expect(lineRow.querySelector('.source-legend__swatch--outside-tests')).not.toBeNull();
  });

  test('threads contexts into materialized source files', async () => {
    await boot(withContexts());
    const el = materializeSourceFile(fileId('lib/covered.rb'))!;

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
    expect(materializeSourceFile(fileId('lib/covered.rb'))!.querySelector('button.hits--tests')).toBeNull();
  });
});

describe('footer run names', () => {
  test('summarizes many runs behind a disclosure', async () => {
    const data = coverageData();
    data.meta.command_names = ['RSpec a', 'RSpec b', 'RSpec c', 'RSpec d', 'RSpec e'];
    await boot(data);

    const footer = document.getElementById('footer')!;
    const details = footer.querySelector('details.footer-runs')!;
    expect(details).not.toBeNull();
    expect(details.querySelector('summary')!.textContent).toBe('RSpec a and 4 other runs');
    expect(details.querySelector('.footer-runs__list')!.textContent)
      .toBe('RSpec a, RSpec b, RSpec c, RSpec d, RSpec e');
    expect(document.getElementById('source-dialog-footer')!.innerHTML).toBe(footer.innerHTML);
  });

  test('renders a few distinct runs inline, without a disclosure', async () => {
    const data = coverageData();
    data.meta.command_names = ['Cucumber', 'RSpec', 'Minitest'];
    await boot(data);

    const footer = document.getElementById('footer')!;
    expect(footer.textContent).toContain('using Cucumber, RSpec, Minitest');
    expect(footer.querySelector('details')).toBeNull();
  });

  test('escapes run names in both branches', async () => {
    const data = coverageData();
    data.meta.command_names = ['<b>1</b>', '<b>2</b>', '<b>3</b>', '<b>4</b>'];
    await boot(data);

    const footer = document.getElementById('footer')!;
    expect(footer.querySelector('b')).toBeNull();
    expect(footer.querySelector('summary')!.textContent).toBe('<b>1</b> and 3 other runs');
  });

  test('falls back to the joined command_name for documents without the array', async () => {
    const data = coverageData();
    delete data.meta.command_names;
    await boot(data);

    const footer = document.getElementById('footer')!;
    expect(footer.textContent).toContain('using RSpec');
    expect(footer.querySelector('details')).toBeNull();
  });
});

describe('an embedded run history', () => {
  test('is carried as data only, with no trend column in the file list', async () => {
    const data = coverageData();
    data.history = [
      { created_at: '2026-08-24T00:00:00Z', totals: { line: 60 } },
      { created_at: '2026-08-25T00:00:00Z', totals: { line: 71.42 } }
    ];
    await boot(data);

    expect(document.querySelector('.t-trend-h')).toBeNull();
    expect(document.querySelector('.sparkline')).toBeNull();
  });
});

describe('renderPage with production coverage', () => {
  function withProduction() {
    const data = coverageData();
    data.production = {
      started_at: '2026-08-01T05:00:00Z',
      updated_at: '2026-08-25T11:00:00Z',
      files: { 'lib/covered.rb': { lines: [1, 2], last_seen: '2026-08-25T10:00:00Z' } }
    };
    return data;
  }

  test('adds the production legend row exactly when the section is present', async () => {
    await boot(coverageData());
    expect(document.getElementById('source-legend')!.textContent).not.toContain('production');

    installPageSkeleton();
    await boot(withProduction());
    const legend = document.getElementById('source-legend')!;
    expect(legend.children).toHaveLength(2);
    const row = legend.querySelector('.source-legend__row--production')!;
    const labels = Array.from(row.querySelectorAll('.source-legend__item'), (item) => item.textContent);
    expect(labels).toEqual(['Never ran in production', 'Untested, runs in production']);
    expect(row.querySelector('.source-legend__swatch--production-never')).not.toBeNull();
    expect(row.querySelector('.source-legend__swatch--production-ran')).not.toBeNull();
  });

  test('renders the last-run column in every file list', async () => {
    await boot(withProduction());
    const cells = document.querySelectorAll('#g-total tbody td.cell--production');
    expect(cells).toHaveLength(2);
    expect(cells[0].textContent).toBe('2026-08-25');
    expect(cells[1].textContent).toBe('never');
  });

  test('threads each file\'s entry into materialized source views', async () => {
    await boot(withProduction());
    const seen = materializeSourceFile(fileId('lib/covered.rb'))!;
    expect(seen.querySelector('li.production-ran')).not.toBeNull();
    expect(seen.querySelector('.t-production-summary')!.textContent).toContain('last run 2026-08-25');

    const unseen = materializeSourceFile(fileId('lib/missed.rb'))!;
    expect(unseen.querySelectorAll('li.production-never').length).toBeGreaterThan(0);
    expect(unseen.querySelector('li.production-ran')).toBeNull();
  });

  test('threads nothing when the report carries no section', async () => {
    await boot(coverageData());
    const el = materializeSourceFile(fileId('lib/covered.rb'))!;
    expect(el.querySelector('[class*="production"]')).toBeNull();
  });
});
