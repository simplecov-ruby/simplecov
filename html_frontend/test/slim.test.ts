import { describe, expect, test } from 'bun:test';
import hljs from 'highlight.js/lib/core';
import ruby from 'highlight.js/lib/languages/ruby';
import slim from '../src/slim';

const h = hljs.newInstance();
h.registerLanguage('ruby', ruby);
h.registerLanguage('slim', slim);

function highlight(code: string): string {
  return h.highlight(code, {language: 'slim'}).value;
}

describe('slim grammar', () => {
  test('is named Slim', () => {
    expect(h.getLanguage('slim')!.name).toBe('Slim');
  });

  test('marks slash comments at any indentation, including HTML comments', () => {
    expect(highlight('/ comment')).toBe('<span class="hljs-comment">/ comment</span>');
    expect(highlight('  / indented')).toBe('<span class="hljs-comment">  / indented</span>');
    expect(highlight('/! html')).toBe('<span class="hljs-comment">/! html</span>');
  });

  test('leaves a slash inside text alone', () => {
    expect(highlight('| a / b = c')).toBe('| a / b = c');
  });

  test('hands the rest of a control or output line to Ruby, keeping the marker outside', () => {
    expect(highlight('- if @a')).toBe('-<span class="language-ruby"> <span class="hljs-keyword">if</span> @a</span>');
    expect(highlight('= @x')).toBe('=<span class="language-ruby"> @x</span>');
    expect(highlight('  = @x')).toBe('  =<span class="language-ruby"> @x</span>');
    expect(highlight('== @raw')).toBe('==<span class="language-ruby"> @raw</span>');
    expect(highlight("=' @x")).toBe('=&#x27;<span class="language-ruby"> @x</span>');
  });

  test('does not treat an equals sign inside a tag line as Ruby', () => {
    expect(highlight('a href="/x"')).toBe('<span class="hljs-name">a</span> href=&quot;/x&quot;');
    expect(highlight('p text = x')).toBe('<span class="hljs-name">p</span> text = x');
  });

  test('names the tag at any indentation and nothing after it', () => {
    expect(highlight('h1 Hello')).toBe('<span class="hljs-name">h1</span> Hello');
    expect(highlight('  p Hello')).toBe('<span class="hljs-name">  p</span> Hello');
    expect(highlight('h1 Hello\n  p World\n')).toBe(
      '<span class="hljs-name">h1</span> Hello\n<span class="hljs-name">  p</span> World\n'
    );
  });

  test('splits a tag shortcut into name, class, and id', () => {
    expect(highlight('div.foo-1#bar_2 text')).toBe(
      '<span class="hljs-name">div</span><span class="hljs-selector-class">.foo-1</span>' +
      '<span class="hljs-selector-id">#bar_2</span> text'
    );
    expect(highlight('div.foo')).toBe('<span class="hljs-name">div</span><span class="hljs-selector-class">.foo</span>');
  });

  test('ignores dots and hashes in tag content', () => {
    expect(highlight('p a.b c#d')).toBe('<span class="hljs-name">p</span> a.b c#d');
    expect(highlight('div.foo .bar')).toBe('<span class="hljs-name">div</span><span class="hljs-selector-class">.foo</span> .bar');
  });

  test('marks class and id shortcuts that open a line, at any indentation', () => {
    expect(highlight('.foo-bar text')).toBe('<span class="hljs-selector-class">.foo-bar</span> text');
    expect(highlight('  .foo text')).toBe('<span class="hljs-selector-class">  .foo</span> text');
    expect(highlight('#main')).toBe('<span class="hljs-selector-id">#main</span>');
    expect(highlight('  #main-1 text')).toBe('<span class="hljs-selector-id">  #main-1</span> text');
  });
});
