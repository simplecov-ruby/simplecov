// A small Slim grammar for highlight.js, which ships none.
//
// Slim is indentation-driven and the report highlights one line at a time, so
// this reads a line by what it starts with: a control or output marker is
// Ruby, a slash is a comment, a pipe or apostrophe is verbatim text, and
// anything else opens with a tag name and its shorthand classes and id.
//
// It deliberately stops at the first space after the tag. What follows is
// either attributes or text, and telling the two apart on one line is where a
// hand-written grammar starts guessing: `h1 = @foo.bar` and `a href="/x"` put
// different things on either side of the same `=`. Leaving the tail plain
// costs a little colour on the attributes and never mislabels anything, which
// is the better trade in a report whose subject is the code. It is also about
// what highlight.js's own Haml grammar does with the same construct.

import type { HLJSApi, Language } from 'highlight.js';

export default function slim(hljs: HLJSApi): Language {
  return {
    name: 'Slim',
    contains: [
      hljs.COMMENT(/^\s*\/!?/, /$/),
      {
        // `-` runs code, `=` outputs it, `==` outputs it without escaping,
        // and any of them may trail `<` or `>` for whitespace control.
        begin: /^\s*(?:-|={1,2})[<>']*/,
        end: /$/,
        subLanguage: 'ruby',
        excludeBegin: true,
        relevance: 0
      },
      { begin: /^\s*[|']/, end: /$/, relevance: 0 },
      {
        className: 'name',
        begin: /^\s*[A-Za-z][A-Za-z0-9_-]*/,
        relevance: 0,
        starts: {
          end: /\s|$/,
          relevance: 0,
          contains: [
            { className: 'selector-class', begin: /\.[A-Za-z][A-Za-z0-9_-]*/, relevance: 0 },
            { className: 'selector-id', begin: /#[A-Za-z][A-Za-z0-9_-]*/, relevance: 0 }
          ]
        }
      },
      // A line opening with the shorthand instead of a tag name, which Slim
      // reads as a div.
      { className: 'selector-class', begin: /^\s*\.[A-Za-z][A-Za-z0-9_-]*/, relevance: 0 },
      { className: 'selector-id', begin: /^\s*#[A-Za-z][A-Za-z0-9_-]*/, relevance: 0 }
    ]
  };
}
