import { beforeEach, describe, expect, test } from 'bun:test';
import { toggleTestsPeek, closeTestsPeek, setupTestsPeekDismissal } from '../src/tests_peek';

function buildSourceTable(): { table: HTMLElement; badges: HTMLElement[] } {
  document.body.innerHTML = `
    <div class="source_table" id="f-abc">
      <pre><ol>
        <li class="covered" data-linenumber="1">
          <button type="button" class="hits hits--tests" data-content="2 tests" data-tests-line="1" aria-expanded="false"></button>
          <code>a</code>
        </li>
        <li class="outside-tests" data-linenumber="2">
          <button type="button" class="hits hits--tests hits--tests-none" data-content="0 tests" data-tests-line="2" aria-expanded="false"></button>
          <code>b</code>
        </li>
      </ol></pre>
    </div>`;
  const table = document.getElementById('f-abc')!;
  return { table, badges: Array.from(table.querySelectorAll('button.hits--tests')) };
}

const resolver = (sourceFileId: string, line: number): string[] | null => {
  if (sourceFileId !== 'f-abc') return null;
  return line === 1 ? ['spec/a_spec.rb:12', 'spec/b_spec.rb:9'] : [];
};

describe('toggleTestsPeek', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
  });

  test('opens a peek panel after the line, listing the sorted ids', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], resolver);

    const peek = document.querySelector('li.tests-peek')!;
    expect(peek.previousElementSibling).toBe(badges[0].closest('li'));
    expect(peek.textContent).toContain('Covered by 2 tests');
    const ids = Array.from(peek.querySelectorAll('code')).map((c) => c.textContent);
    expect(ids).toEqual(['spec/a_spec.rb:12', 'spec/b_spec.rb:9']);
    expect(badges[0].getAttribute('aria-expanded')).toBe('true');
  });

  test('explains a drained line instead of listing nothing', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[1], resolver);

    const peek = document.querySelector('li.tests-peek')!;
    expect(peek.textContent).toContain('No recorded test covers this line');
    expect(peek.querySelector('code')).toBeNull();
  });

  test('toggles closed from the same badge and keeps one peek at a time', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], resolver);
    toggleTestsPeek(badges[1], resolver);
    expect(document.querySelectorAll('li.tests-peek').length).toBe(1);
    expect(badges[0].getAttribute('aria-expanded')).toBe('false');

    toggleTestsPeek(badges[1], resolver);
    expect(document.querySelector('li.tests-peek')).toBeNull();
    expect(badges[1].getAttribute('aria-expanded')).toBe('false');
  });

  test('explains the drained line in a note', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[1], resolver);
    expect(document.querySelector('li.tests-peek .tests-peek__note')!.textContent)
      .toBe('It ran outside any test: at load time, in suite setup, or from a helper.');
  });

  test('titles a single test in the singular', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], () => ['spec/only_spec.rb:3']);
    expect(document.querySelector('li.tests-peek .tests-peek__title')!.textContent).toBe('Covered by 1 test');
  });

  test('lists the ids with nothing between them', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], resolver);
    expect(document.querySelector('li.tests-peek ul')!.textContent).toBe('spec/a_spec.rb:12spec/b_spec.rb:9');
  });

  test('ignores a badge outside a source table', () => {
    document.body.innerHTML = '<ol><li><button class="hits--tests" data-tests-line="1"></button></li></ol>';
    const badge = document.querySelector('button') as HTMLElement;
    expect(() => toggleTestsPeek(badge, resolver)).not.toThrow();
    expect(document.querySelector('li.tests-peek')).toBeNull();
  });

  test('ignores a badge outside a line', () => {
    document.body.innerHTML = '<div class="source_table" id="f-abc"><button class="hits--tests" data-tests-line="1"></button></div>';
    const badge = document.querySelector('button') as HTMLElement;
    expect(() => toggleTestsPeek(badge, resolver)).not.toThrow();
    expect(document.querySelector('li.tests-peek')).toBeNull();
  });

  test('opens nothing when the resolver has no answer', () => {
    const { badges } = buildSourceTable();
    expect(() => toggleTestsPeek(badges[0], () => null)).not.toThrow();
    expect(document.querySelector('li.tests-peek')).toBeNull();
    expect(badges[0].getAttribute('aria-expanded')).toBe('false');
  });

  test('escapes the ids it renders', () => {

    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], () => ['<img src=x>']);
    expect(document.querySelector('li.tests-peek img')).toBeNull();
    expect(document.querySelector('li.tests-peek code')!.textContent).toBe('<img src=x>');
  });
});

describe('dismissal', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
    setupTestsPeekDismissal();
  });

  test('Escape closes the peek and stays inside the dialog', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], resolver);

    const event = new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true });
    document.dispatchEvent(event);

    expect(document.querySelector('li.tests-peek')).toBeNull();
    expect(event.defaultPrevented).toBe(true);
  });

  test('a click outside the peek closes it; a click inside does not', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], resolver);

    document.querySelector('li.tests-peek code')!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(document.querySelector('li.tests-peek')).not.toBeNull();

    document.body.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(document.querySelector('li.tests-peek')).toBeNull();
  });

  test('other keys leave the peek open', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], resolver);
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'a', bubbles: true }));
    expect(document.querySelector('li.tests-peek')).not.toBeNull();
  });

  test('Escape is captured before the badge and stopped from reaching it', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], resolver);
    let reached = 0;
    badges[0].addEventListener('keydown', (event) => {
      reached++;
      event.stopPropagation();
    });

    badges[0].dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));

    expect(document.querySelector('li.tests-peek')).toBeNull();
    expect(reached).toBe(0);
  });

  test('a click on the badge itself is left to the badge', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], resolver);
    badges[0].addEventListener('click', (event) => event.stopPropagation());
    badges[0].dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(document.querySelector('li.tests-peek')).not.toBeNull();
  });

  test('an outside click is captured before its target can swallow it', () => {
    const { badges } = buildSourceTable();
    toggleTestsPeek(badges[0], resolver);
    document.body.addEventListener('click', (event) => event.stopPropagation());
    document.body.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(document.querySelector('li.tests-peek')).toBeNull();
  });

  test('a click with nothing open is ignored', () => {
    buildSourceTable();
    let errors = 0;
    const count = (): void => { errors++; };
    window.addEventListener('error', count);
    document.body.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    window.removeEventListener('error', count);
    expect(errors).toBe(0);
  });

  test('closeTestsPeek is safe with nothing open', () => {

    expect(() => closeTestsPeek()).not.toThrow();
  });
});
