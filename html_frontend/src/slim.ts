
import type { HLJSApi, Language } from 'highlight.js';

export default function slim(hljs: HLJSApi): Language {
  return {
    name: 'Slim',
    contains: [
      hljs.COMMENT(/^\s*\/!?/, /$/),
      {
        begin: /^\s*(?:-|={1,2})[<>']*/,
        end: /$/,
        subLanguage: 'ruby',
        excludeBegin: true,
        relevance: 0
      },
      {
        className: 'name',
        begin: /^\s*[A-Za-z][A-Za-z0-9_-]*/,
        relevance: 0,
        starts: {
          end: /\s/,
          relevance: 0,
          contains: [
            { className: 'selector-class', begin: /\.[A-Za-z][A-Za-z0-9_-]*/, relevance: 0 },
            { className: 'selector-id', begin: /#[A-Za-z][A-Za-z0-9_-]*/, relevance: 0 }
          ]
        }
      },
      { className: 'selector-class', begin: /^\s*\.[A-Za-z][A-Za-z0-9_-]*/, relevance: 0 },
      { className: 'selector-id', begin: /^\s*#[A-Za-z][A-Za-z0-9_-]*/, relevance: 0 }
    ]
  };
}
