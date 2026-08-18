// The inline peek panel behind each tests badge: an extra list row under
// the source line naming the tests that cover it — deliberately the same
// ids, in the same order, that `simplecov tests <file>:<line>` prints, so
// the report and the CLI give one answer. One peek is open at a time; its
// badge toggles it, Escape or a click elsewhere dismisses it.

import { escapeHTML } from './dom';

export type PeekResolver = (sourceFileId: string, line: number) => string[] | null;

let openPeek: HTMLElement | null = null;
let openBadge: HTMLElement | null = null;

function renderPeek(ids: string[]): string {
  if (ids.length === 0) {
    return '<div class="tests-peek__title">No recorded test covers this line</div>' +
      '<div class="tests-peek__note">It ran outside any test: at load time, in suite setup, or from a helper.</div>';
  }
  const title = ids.length === 1 ? 'Covered by 1 test' : `Covered by ${ids.length} tests`;
  return `<div class="tests-peek__title">${title}</div>` +
    `<ul class="tests-peek__list">${ids.map((id) => `<li><code>${escapeHTML(id)}</code></li>`).join('')}</ul>`;
}

export function closeTestsPeek(): void {
  if (openPeek) openPeek.remove();
  if (openBadge) openBadge.setAttribute('aria-expanded', 'false');
  openPeek = null;
  openBadge = null;
}

export function toggleTestsPeek(badge: HTMLElement, resolve: PeekResolver): void {
  const line = badge.closest('li');
  const table = badge.closest('.source_table');
  if (!line || !table) return;

  const reopening = openBadge === badge;
  closeTestsPeek();
  if (reopening) return;

  const lineNumber = Number(badge.getAttribute('data-tests-line'));
  const ids = resolve(table.id, lineNumber);
  if (!ids) return;

  const peek = document.createElement('li');
  peek.className = 'tests-peek';
  peek.innerHTML = renderPeek(ids);
  line.after(peek);

  badge.setAttribute('aria-expanded', 'true');
  openPeek = peek;
  openBadge = badge;
}

// Escape closes the peek before anything else sees it — inside the source
// dialog, an unguarded Escape would close the whole dialog instead. A
// click anywhere outside the peek (its own badge toggles itself) also
// dismisses it. Registered once at boot; both handlers are no-ops while
// nothing is open.
export function setupTestsPeekDismissal(): void {
  document.addEventListener('keydown', (event) => {
    if (!openPeek || event.key !== 'Escape') return;
    event.preventDefault();
    event.stopPropagation();
    closeTestsPeek();
  }, true);

  document.addEventListener('click', (event) => {
    if (!openPeek) return;
    const target = event.target as Element;
    if (openPeek.contains(target) || target === openBadge || openBadge?.contains(target)) return;
    closeTestsPeek();
  }, true);
}
