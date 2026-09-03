import { beforeAll, describe, expect, test } from 'bun:test';
import { fileId, precomputeFileIds } from '../src/format';
import { languageFor, renderSourceFile } from '../src/render_source';
import type { FileCoverage, ProductionFileEntry } from '../src/types';

const FILE = 'lib/<source>.rb'; // markup-significant name to prove escaping
const TEMPLATE = 'app/views/foos/show.html.erb';

beforeAll(async () => {
  await precomputeFileIds([FILE, TEMPLATE]);
});

function render(
  data: FileCoverage,
  line = true,
  branch = true,
  method = true
): HTMLElement {
  const el = document.createElement('div');
  el.innerHTML = renderSourceFile(FILE, data, line, branch, method);
  return el.firstElementChild as HTMLElement;
}

const data: FileCoverage = {
  source: ['if a', 'elsif b', 'def m1', 'end', ':skipped', ':missed', '# comment', 'trailing'],
  lines: [2, 1, 1, 1, 'ignored', 0, null],
  covered_lines: 5,
  total_lines: 6,
  branches: [
    { type: 'then', start_line: 1, end_line: 1, coverage: 3, inline: true, report_line: 1 },
    { type: 'elsif<', start_line: 2, end_line: 2, coverage: 0, inline: true, report_line: 2 },
    { type: 'else', start_line: 2, end_line: 2, coverage: 1, inline: true, report_line: 2 },
    { type: 'when', start_line: 5, end_line: 5, coverage: 'ignored', inline: true, report_line: 5 }
  ],
  covered_branches: 2,
  total_branches: 3,
  methods: [
    { name: '<Foo>#missed', start_line: 3, end_line: 4, coverage: 0 },
    { name: 'Foo#covered', start_line: 1, end_line: 1, coverage: 7 }
  ],
  covered_methods: 1,
  total_methods: 2
};

describe('renderSourceFile', () => {
  test('classifies every line status', () => {
    const statuses = Array.from(render(data).querySelectorAll('ol li')).map((li) => li.className);
    expect(statuses).toEqual([
      'covered',
      'missed-branch',
      'missed-method',
      'missed-method',
      'skipped',
      'missed',
      'never',
      'never'
    ]);
  });

  test('renders hit counts, skip markers, and escaped branch annotations', () => {
    const lis = render(data).querySelectorAll('ol li');

    expect(lis[0].getAttribute('data-hits')).toBe('2');
    expect(lis[0].getAttribute('data-linenumber')).toBe('1');
    expect(lis[0].querySelector('.hits')!.getAttribute('data-content')).toBe('2');
    expect(lis[0].querySelector('code.ruby')!.textContent).toBe('if a');

    const branchHits = Array.from(lis[1].querySelectorAll('.hits')).map((s) =>
      s.getAttribute('data-content')
    );
    expect(branchHits).toEqual(['1', 'elsif<: 0', 'else: 1']);
    expect(lis[1].querySelectorAll('.hits')[1]!.getAttribute('title')).toBe(
      'elsif< branch hit 0 times'
    );

    expect(lis[4].querySelectorAll('.hits')).toHaveLength(1);
    expect(lis[4].querySelector('.hits')!.getAttribute('data-content')).toBe('skipped');
    expect(lis[4].getAttribute('data-hits')).toBeNull();
    expect(lis[5].getAttribute('data-hits')).toBe('0');
    expect(lis[5].querySelector('.hits')).toBeNull();
    expect(lis[6].getAttribute('data-hits')).toBeNull();
    expect(lis[6].outerHTML).toStartWith('<li class="never" data-linenumber="7">');
    expect(lis[0].textContent).toBe('if a');
  });

  test('keeps the rows as the only children of the list', () => {
    const el = render(data);
    expect(el.firstChild).toBe(el.querySelector('.header'));
    const ol = el.querySelector('pre > ol')!;
    expect(ol.parentElement!.parentElement).toBe(el);
    expect(ol.childNodes).toHaveLength(8);
    expect(renderSourceFile(FILE, data, true, true, true)).toEndWith('</ol></pre></div>');
  });

  test('renders the header summary and the hidden missed-method toggle list', () => {
    const el = render(data);
    expect(el.id).toBe(fileId(FILE));
    expect(el.querySelector('.header h2')!.textContent).toBe(FILE);
    const summary = el.querySelector('.summary-stats')!.textContent;
    expect(summary).toContain('5/6 relevant lines covered');
    expect(summary).toContain('Branch coverage: 66.66% 2/3 covered');
    expect(summary).toContain('Method coverage: 50.00% 1/2 covered');
    expect(el.querySelector('.t-missed-method-toggle')).not.toBeNull();

    const list = el.querySelector('.t-missed-method-list') as HTMLElement;
    expect(list.style.display).toBe('none');
    expect(list.textContent).toBe('<Foo>#missed');
    expect(list.querySelector('pre')).toBeNull();
  });

  test('lists every missed method back to back', () => {
    const list = render({
      source: ['def a', 'end', 'def b', 'end'],
      lines: [0, null, 0, null],
      methods: [
        { name: 'Foo#a', start_line: 1, end_line: 2, coverage: 0 },
        { name: 'Foo#b', start_line: 3, end_line: 4, coverage: 0 }
      ],
      covered_methods: 0,
      total_methods: 2
    }).querySelector('.t-missed-method-list')!;
    expect(list.textContent).toBe('Foo#aFoo#b');
    expect(list.querySelectorAll('li')).toHaveLength(2);
  });

  test('ignores missed branches when branch coverage is off', () => {
    const statuses = Array.from(render(data, true, false, true).querySelectorAll('ol li')).map((li) => li.className);
    expect(statuses[1]).toBe('covered');
    expect(render(data, true, false, true).querySelectorAll('ol li')[1].querySelectorAll('.hits')).toHaveLength(1);
  });

  test('handles disabled criteria and a file without line data', () => {
    const el = render({ source: ['a', 'b'] }, false, false, false);
    const statuses = Array.from(el.querySelectorAll('ol li')).map((li) => li.className);
    expect(statuses).toEqual(['never', 'never']);
    expect(el.querySelector('.t-missed-method-list')).toBeNull();
    expect(el.querySelectorAll('.summary-stats .coverage-disabled')).toHaveLength(3);
  });

  test('shows no toggle when method coverage is on but the file has no methods', () => {
    const el = render({ source: ['a'], lines: [1] });
    expect(el.querySelector('.t-missed-method-toggle')).toBeNull();
    expect(el.querySelector('.t-missed-method-list')).toBeNull();
  });

  test('skips the toggle list when method coverage is on but nothing is missed', () => {
    const el = render({
      source: ['def ok', 'end'],
      lines: [1, null],
      methods: [{ name: 'Foo#ok', start_line: 1, end_line: 2, coverage: 3 }],
      covered_methods: 1,
      total_methods: 1
    });
    expect(el.querySelector('.t-missed-method-toggle')).toBeNull();
    expect(el.querySelector('.t-missed-method-list')).toBeNull();
  });

  test("tags each line with the file's highlighting language", () => {
    const el = document.createElement('div');
    el.innerHTML = renderSourceFile(TEMPLATE, { source: ['<h1><%= @foo %></h1>'], lines: [1] }, true, false, false);
    expect(el.querySelector('code.erb')!.textContent).toBe('<h1><%= @foo %></h1>');
  });
});

describe('languageFor', () => {
  test('marks templates as their own language and everything else as Ruby', () => {
    expect(languageFor('app/views/foos/show.html.erb')).toBe('erb');
    expect(languageFor('app/views/foos/SHOW.HTML.ERB')).toBe('erb');
    expect(languageFor('app/views/foos/show.html.haml')).toBe('haml');
    expect(languageFor('app/views/foos/show.html.slim')).toBe('slim');
    expect(languageFor('lib/simplecov.rb')).toBe('ruby');
    expect(languageFor('Rakefile')).toBe('ruby');
  });
});

describe('renderSourceFile with recorded contexts', () => {
  const contexts = ['spec/b_spec.rb:9', 'spec/a_spec.rb:12'];

  function renderCtx(data: FileCoverage, ctx: string[] | undefined = contexts): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML = renderSourceFile(FILE, data, true, false, false, ctx);
    return el.firstElementChild as HTMLElement;
  }

  const ctxData: FileCoverage = {
    source: ['a', 'b', 'c', '# d'],
    lines: [1, 2, 0, null],
    covered_lines: 2,
    total_lines: 3,
    contexts: { '0': '1', '1': '1' }
  };

  test('adds a tests badge to covered lines, naming the count', () => {
    const lines = Array.from(renderCtx(ctxData).querySelectorAll('ol li'));
    const badge = lines[0].querySelector('button.hits--tests')!;
    expect(badge.getAttribute('data-content')).toBe('2 tests');
    expect(badge.getAttribute('data-tests-line')).toBe('1');
    expect(badge.classList.contains('hits--tests-none')).toBe(false);
    expect(lines[2].querySelector('button.hits--tests')).toBeNull();
    expect(lines[3].querySelector('button.hits--tests')).toBeNull();
  });

  test('drains a covered line no recorded test executed', () => {
    const lines = Array.from(renderCtx(ctxData).querySelectorAll('ol li'));
    expect(lines[1].className).toBe('outside-tests');
    const badge = lines[1].querySelector('button.hits--tests')!;
    expect(badge.getAttribute('data-content')).toBe('0 tests');
    expect(badge.classList.contains('hits--tests-none')).toBe(true);
  });

  test('gives an ignored line no badge and leaves it out of the attribution', () => {
    const skipped: FileCoverage = {
      source: ['a', ':skip'], lines: [1, 'ignored'], covered_lines: 1, total_lines: 1, contexts: { '0': '1' }
    };
    const table = renderCtx(skipped);
    const lines = Array.from(table.querySelectorAll('ol li'));
    expect(lines[1].className).toBe('skipped');
    expect(lines[1].querySelector('button.hits--tests')).toBeNull();
    expect(table.querySelector('.t-line-summary')!.textContent).toContain('1/1 relevant lines covered by tests');
  });

  test('uses the singular for a single covering test', () => {
    const one: FileCoverage = { source: ['a'], lines: [1], covered_lines: 1, total_lines: 1, contexts: { '1': '1' } };
    const badge = renderCtx(one).querySelector('button.hits--tests')!;
    expect(badge.getAttribute('data-content')).toBe('1 test');
  });

  test('keeps branch and method misses ranked above the drained status', () => {
    const el = document.createElement('div');
    el.innerHTML = renderSourceFile(FILE, {
      source: ['if a', 'end'],
      lines: [1, 1],
      covered_lines: 2,
      total_lines: 2,
      branches: [{ type: 'then', start_line: 1, end_line: 1, coverage: 0, inline: true, report_line: 1 }],
      covered_branches: 0,
      total_branches: 1,
      contexts: {}
    }, true, true, false, contexts);
    const lines = Array.from((el.firstElementChild as HTMLElement).querySelectorAll('ol li'));
    expect(lines[0].className).toBe('missed-branch');
    expect(lines[1].className).toBe('outside-tests');
  });

  test('counts a no-test line as outside even when a branch miss outranks its color', () => {
    const el = document.createElement('div');
    el.innerHTML = renderSourceFile(FILE, {
      source: ['if a', 'end'],
      lines: [1, 1],
      covered_lines: 2,
      total_lines: 2,
      branches: [{ type: 'then', start_line: 1, end_line: 1, coverage: 0, inline: true, report_line: 1 }],
      covered_branches: 0,
      total_branches: 1,
      contexts: {}
    }, true, true, false, contexts);
    const header = (el.firstElementChild as HTMLElement).querySelector('.summary-stats')!;
    const line = header.querySelector('.t-line-summary')!;
    expect(line.textContent).toContain('0/2 relevant lines covered by tests');
    expect(line.textContent).toContain('2/2 relevant lines covered outside tests');
  });

  test('splits the line summary by test attribution', () => {
    const header = renderCtx(ctxData).querySelector('.summary-stats')!;
    const line = header.querySelector('.t-line-summary')!;
    expect(header.querySelector('.t-tests-summary')).toBeNull();
    expect(line.textContent).toContain('Line coverage:');
    expect(line.textContent).toContain('66.66%');
    expect(line.textContent).toContain('1/3 relevant lines covered by tests');
    expect(line.textContent).toContain('1/3 relevant lines covered outside tests');
    expect(line.textContent).toContain('1 missed');
    const outside = line.querySelector('.outside-tests-text')!;
    expect(outside.textContent).toBe('1/3 relevant lines covered outside tests');
    expect(outside.className).toBe('coverage-cell__fraction outside-tests-text');
    expect(outside.querySelector('b')).toBeNull();
  });

  test('omits the outside clause when every covered line is covered by tests', () => {
    const all: FileCoverage = {
      source: ['a'], lines: [1], covered_lines: 1, total_lines: 1, contexts: { '0': '1' }
    };
    const line = renderCtx(all).querySelector('.t-line-summary')!;
    expect(line.textContent).toContain('100.00%');
    expect(line.textContent).toContain('1/1 relevant lines covered by tests');
    expect(line.textContent).not.toContain('outside');
    expect(line.textContent).not.toContain('missed');
  });

  test('renders identically to today when no contexts were recorded', () => {
    const el = document.createElement('div');
    el.innerHTML = renderSourceFile(FILE, ctxData, true, false, false);
    const rendered = el.firstElementChild as HTMLElement;
    expect(rendered.querySelector('.hits--tests')).toBeNull();
    expect(rendered.querySelector('.outside-tests')).toBeNull();
    expect(rendered.querySelector('.t-tests-summary')).toBeNull();
  });
});

describe('renderSourceFile with production coverage', () => {
  const simple: FileCoverage = {
    source: ['def foo', '  :bar', '  :baz', 'end'],
    lines: [1, 1, 0, null],
    covered_lines: 2,
    total_lines: 3
  };

  function renderProduction(production?: ProductionFileEntry | null): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML = renderSourceFile(FILE, simple, true, false, false, undefined, production);
    return el.firstElementChild as HTMLElement;
  }

  test('crosses each relevant line with the production window', () => {
    const table = renderProduction({ lines: [1, 3], last_seen: '2026-08-25T10:30:00Z' });
    const lines = table.querySelectorAll('pre li');
    expect(lines[0].className).toBe('covered production-ran');
    expect(lines[1].className).toBe('covered production-never');
    expect(lines[2].className).toBe('missed production-ran');
    expect(lines[3].className).toBe('never');
  });

  test('badges untested code the window ran, and only that', () => {
    const table = renderProduction({ lines: [1, 3] });
    const badges = table.querySelectorAll('.hits--production');
    expect(badges).toHaveLength(1);
    expect(badges[0].getAttribute('data-content')).toBe('runs in production');
    expect(badges[0].closest('li')!.getAttribute('data-linenumber')).toBe('3');
  });

  test('summarizes the ran share and the last-run date in the header', () => {
    const table = renderProduction({ lines: [1, 3], last_seen: '2026-08-25T10:30:00Z' });
    const summary = table.querySelector('.summary-stats--production > .t-production-summary')!;
    expect(summary.textContent).toContain('Production: 2/3 relevant lines ran');
    expect(summary.textContent).toContain('last run 2026-08-25');
    expect(summary.querySelector('[title="2026-08-25T10:30:00Z"]')!.textContent).toBe('2026-08-25');
    expect(table.querySelector('.summary-stats--production pre')).toBeNull();
    expect(table.querySelector('.summary-stats--production')!.children).toHaveLength(1);
    expect(table.querySelector('pre')!.parentElement).toBe(table);
  });

  test('omits the last-run clause for a stamp-less entry', () => {
    const summary = renderProduction({ lines: [1] })
      .querySelector('.t-production-summary')!;
    expect(summary.textContent).toContain('1/3 relevant lines ran');
    expect(summary.textContent).not.toContain('last run');
  });

  test('marks every relevant line of a file the window never saw', () => {
    const table = renderProduction(null);
    const lines = table.querySelectorAll('pre li');
    expect(lines[0].className).toBe('covered production-never');
    expect(lines[2].className).toBe('missed production-never');
    expect(table.querySelector('.hits--production')).toBeNull();
    expect(table.querySelector('.t-production-summary')!.textContent).toContain('0/3 relevant lines ran');
  });

  test('renders identically to today when the report carries no section', () => {
    const table = renderProduction(undefined);
    expect(table.querySelector('[class*="production"]')).toBeNull();
  });
});
