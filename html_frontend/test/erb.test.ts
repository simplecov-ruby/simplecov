import { describe, expect, test } from 'bun:test';
import hljs from 'highlight.js/lib/core';
import ruby from 'highlight.js/lib/languages/ruby';
import erb from '../src/erb';

const h = hljs.newInstance();
h.registerLanguage('ruby', ruby);
h.registerLanguage('erb', erb);

function highlight(code: string): string {
  return h.highlight(code, {language: 'erb'}).value;
}

const RUBY_X = '<span class="language-ruby"> <span class="hljs-variable">@x</span> </span>';

describe('erb grammar', () => {
  test('is named ERB', () => {
    expect(h.getLanguage('erb')!.name).toBe('ERB');
  });

  test('marks an ERB comment and stops at its close', () => {
    expect(highlight('<%# note %> after')).toBe('<span class="hljs-comment">&lt;%# note %&gt;</span> after');
  });

  test('hands the inside of each tag form to Ruby, keeping the delimiters outside', () => {
    expect(highlight('<% if x %>')).toBe(
      '&lt;%<span class="language-ruby"> <span class="hljs-keyword">if</span> x </span>%&gt;'
    );
    expect(highlight('<%= @x %>')).toBe(`&lt;%=${RUBY_X}%&gt;`);
    expect(highlight('<%- x -%>')).toBe('&lt;%-<span class="language-ruby"> x </span>-%&gt;');
    expect(highlight('<%= @x %> tail')).toBe(`&lt;%=${RUBY_X}%&gt; tail`);
  });

  test('marks open, close, and self-closing tags with their names', () => {
    expect(highlight('<p>text</p>')).toBe(
      '<span class="hljs-tag">&lt;<span class="hljs-name">p</span>&gt;</span>text' +
      '<span class="hljs-tag">&lt;/<span class="hljs-name">p</span>&gt;</span>'
    );
    expect(highlight('<br/>')).toBe('<span class="hljs-tag">&lt;<span class="hljs-name">br</span>/&gt;</span>');
  });

  test('leaves a bare less-than sign alone', () => {
    expect(highlight('a < b')).toBe('a &lt; b');
  });

  test('marks attributes with double-quoted, single-quoted, and bare values', () => {
    expect(highlight(`<a href="/x" data-y='z' class=plain>`)).toBe(
      '<span class="hljs-tag">&lt;<span class="hljs-name">a</span> ' +
      '<span class="hljs-attr">href</span>=<span class="hljs-string">&quot;/x&quot;</span> ' +
      '<span class="hljs-attr">data-y</span>=<span class="hljs-string">&#x27;z&#x27;</span> ' +
      '<span class="hljs-attr">class</span>=<span class="hljs-attr">plain</span>&gt;</span>'
    );
  });

  test('closes the tag at its bracket so the text after it is plain', () => {
    expect(highlight('<div class="x">y</div>')).toBe(
      '<span class="hljs-tag">&lt;<span class="hljs-name">div</span> ' +
      '<span class="hljs-attr">class</span>=<span class="hljs-string">&quot;x&quot;</span>&gt;</span>y' +
      '<span class="hljs-tag">&lt;/<span class="hljs-name">div</span>&gt;</span>'
    );
  });

  test('nests an output tag between markup tags', () => {
    expect(highlight('<h1><%= @x %></h1>')).toBe(
      '<span class="hljs-tag">&lt;<span class="hljs-name">h1</span>&gt;</span>' +
      `&lt;%=${RUBY_X}%&gt;` +
      '<span class="hljs-tag">&lt;/<span class="hljs-name">h1</span>&gt;</span>'
    );
  });
});
