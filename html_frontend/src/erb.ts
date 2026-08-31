
import type { HLJSApi, Language, Mode } from 'highlight.js';

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
        begin: /<%[%=-]?/,
        end: /[%-]?%>/,
        subLanguage: 'ruby',
        excludeBegin: true,
        excludeEnd: true
      },
      {
        className: 'tag',
        begin: /<\/?(?=[A-Za-z])/,
        end: /\/?>/,
        contains: [
          { className: 'name', begin: /[A-Za-z][^\s/>]*/, relevance: 0, starts: TAG_INTERNALS }
        ]
      }
    ]
  };
}
