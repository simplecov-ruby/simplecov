import { describe, expect, test } from 'bun:test';
import { $, $$, escapeHTML, on } from '../src/dom';

describe('dom helpers', () => {
  test('query helpers operate on the happy-dom document', () => {
    document.body.innerHTML = '<ul><li class="a">one</li><li class="a">two</li></ul>';
    expect($$('li.a').map((el) => el.textContent)).toEqual(['one', 'two']);
    expect($('li.a')?.textContent).toBe('one');
  });

  test('escapeHTML neutralizes markup-significant characters', () => {
    expect(escapeHTML('<script>&"\'')).toBe('&lt;script&gt;&amp;&quot;&#39;');
  });

  test('query helpers scope to an explicit context element', () => {
    document.body.innerHTML = '<div id="scope"><i class="a"></i></div><i class="a"></i>';
    const scope = document.getElementById('scope')!;
    expect($$('i.a', scope)).toHaveLength(1);
    expect($('i.a', scope)).toBe(scope.firstElementChild);
  });
});

describe('on', () => {
  test('attaches a plain listener when given a function', () => {
    document.body.innerHTML = '<button id="b"></button>';
    const button = document.getElementById('b')!;
    let calls = 0;
    on(button, 'click', () => { calls += 1; });
    button.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(calls).toBe(1);
  });

  test('delegates to the matching ancestor with `this` bound to it', () => {
    document.body.innerHTML = '<div id="root"><button class="x"><span id="inner"></span></button></div>';
    const root = document.getElementById('root')!;
    let context: Element | null = null;
    // oxlint-disable-next-line no-this-alias -- capturing `this` is what this test asserts
    on(root, 'click', 'button.x', function (this: Element) { context = this; });
    document.getElementById('inner')!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(context as Element | null).toBe(document.querySelector('button.x')!);
  });

  test('ignores clicks with no selector match', () => {
    document.body.innerHTML = '<div id="root"><span id="inner"></span></div>';
    const root = document.getElementById('root')!;
    let calls = 0;
    on(root, 'click', 'button.x', () => { calls += 1; });
    document.getElementById('inner')!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(calls).toBe(0);
  });

  test('ignores matches that escape the delegation target', () => {
    document.body.innerHTML = '<div class="outer"><div id="target"><span id="inner"></span></div></div>';
    const target = document.getElementById('target')!;
    let calls = 0;
    on(target, 'click', '.outer', () => { calls += 1; });
    document.getElementById('inner')!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(calls).toBe(0);
  });
});
