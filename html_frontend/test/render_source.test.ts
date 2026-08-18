// Annotated source view: per-line status classification across line, branch,
// and method coverage, hit markers, branch annotations, and the missed-method
// toggle list — ported from the cucumber source-view assertions.
import { beforeAll, describe, expect, test } from 'bun:test';
import { fileId, precomputeFileIds } from '../src/format';
import { renderSourceFile } from '../src/render_source';
import type { FileCoverage } from '../src/types';

const FILE = 'lib/<source>.rb'; // markup-significant name to prove escaping

beforeAll(async () => {
  await precomputeFileIds([FILE]);
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

// One file exercising every line status at once. Line numbers are 1-based:
//   1 covered (with a covered branch), 2 missed branch (line itself covered),
//   3-4 missed method span, 5 skipped (with an ignored branch), 6 missed,
//   7 never (null), 8 never (lines array shorter than source).
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

    // covered-line marker first, then one annotation per branch on the line
    const branchHits = Array.from(lis[1].querySelectorAll('.hits')).map((s) =>
      s.getAttribute('data-content')
    );
    expect(branchHits).toEqual(['1', 'elsif<: 0', 'else: 1']);
    expect(lis[1].querySelectorAll('.hits')[1]!.getAttribute('title')).toBe(
      'elsif< branch hit 0 times'
    );

    expect(lis[4].querySelector('.hits')!.getAttribute('data-content')).toBe('skipped');
    expect(lis[5].getAttribute('data-hits')).toBe('0');
    expect(lis[5].querySelector('.hits')).toBeNull();
    expect(lis[6].getAttribute('data-hits')).toBeNull();
  });

  test('renders the header summary and the hidden missed-method toggle list', () => {
    const el = render(data);
    expect(el.id).toBe(fileId(FILE));
    expect(el.querySelector('.header h2')!.textContent).toBe(FILE);
    expect(el.querySelector('.summary-stats')!.textContent).toContain('5/6 relevant lines covered');
    expect(el.querySelector('.t-missed-method-toggle')).not.toBeNull();

    const list = el.querySelector('.t-missed-method-list') as HTMLElement;
    expect(list.style.display).toBe('none');
    const names = Array.from(list.querySelectorAll('tt')).map((tt) => tt.textContent);
    expect(names).toEqual(['<Foo>#missed']);
  });

  test('handles disabled criteria and a file without line data', () => {
    const el = render({ source: ['a', 'b'] }, false, false, false);
    const statuses = Array.from(el.querySelectorAll('ol li')).map((li) => li.className);
    expect(statuses).toEqual(['never', 'never']);
    expect(el.querySelector('.t-missed-method-list')).toBeNull();
    expect(el.querySelectorAll('.summary-stats .coverage-disabled')).toHaveLength(3);
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
});

describe('renderSourceFile with recorded contexts', () => {
  const contexts = ['spec/b_spec.rb:9', 'spec/a_spec.rb:12'];

  function renderCtx(data: FileCoverage, ctx: string[] | undefined = contexts): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML = renderSourceFile(FILE, data, true, false, false, ctx);
    return el.firstElementChild as HTMLElement;
  }

  // Line 1 covered by both contexts, line 2 covered by none (the drained
  // case), line 3 missed, line 4 non-executable.
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

  test('summarizes the file\'s tests in the header, counting drained lines', () => {
    const header = renderCtx(ctxData).querySelector('.summary-stats')!;
    expect(header.textContent).toContain('Test coverage: 2 tests cover this file');
    expect(header.textContent).toContain('1 line covered outside tests');
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
