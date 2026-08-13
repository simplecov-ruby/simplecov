// A small ERB grammar for highlight.js, in place of the one it ships.
//
// highlight.js's `erb` delegates its markup to the `xml` grammar, which can't
// go in this bundle: the report is a single index.html with the JavaScript
// inlined into a <script> element, and xml's rules for embedded scripts carry
// the literal end-tag sequence that would terminate that element early. The
// asset build refuses such a bundle rather than emit a template that
// truncates at render time. It also costs about 5KB in every report written.
//
// So this covers the part of a view a reader is here for: the Ruby between
// the tags, and enough of the markup around it to tell one from the other.

import type { HLJSApi, Language, Mode } from 'highlight.js';

// Attributes and their values, entered after the tag name and left when the
// tag closes, so that the name is styled as a name and everything following
// it as attributes rather than the other way round.
const TAG_INTERNALS: Mode = {
  endsWithParent: true,
  relevance: 0,
  contains: [
    { className: 'attr', begin: /[A-Za-z_:][-A-Za-z0-9_:.]*/, relevance: 0 },
    {
      className: 'string',
      relevance: 0,
      variants: [{ begin: /"/, end: /"/ }, { begin: /'/, end: /'/ }]
    }
  ]
};

export default function erb(hljs: HLJSApi): Language {
  return {
    name: 'ERB',
    contains: [
      hljs.COMMENT('<%#', '%>'),
      {
        // Every tag flavour opens the same way: `<%`, `<%=`, `<%-`, `<%%`.
        begin: /<%[%=-]?/,
        end: /[%-]?%>/,
        subLanguage: 'ruby',
        excludeBegin: true,
        excludeEnd: true
      },
      {
        className: 'tag',
        // Lookahead for a letter so that a bare `<` in the template text
        // (a comparison inside an unclosed tag, a stray angle bracket) does
        // not open a tag that then runs to the end of the line.
        begin: /<\/?(?=[A-Za-z])/,
        end: /\/?>/,
        contains: [
          { className: 'name', begin: /[A-Za-z][^\s/>]*/, relevance: 0, starts: TAG_INTERNALS }
        ]
      }
    ]
  };
}
