
import { escapeHTML } from './dom';

export interface LineContexts {
  tests: string[];
  loading: string[];
}

export type PeekResolver = (sourceFileId: string, line: number) => LineContexts | null;

let openPeek: HTMLElement | null = null;
let openBadge: HTMLElement | null = null;

function renderIds(ids: string[]): string {
  return `<ul class="tests-peek__list">${ids.map((id) => `<li><code>${escapeHTML(id)}</code></li>`).join('')}</ul>`;
}

// A test file's own loading is listed apart from the tests, since running
// the file runs its tests, not just what it did while defining them.
function renderLoading(loading: string[], also: boolean): string {
  if (loading.length === 0) return '';
  const lead = also ? 'It also ran while' : 'It ran while';
  const files = loading.length === 1 ? 'this test file' : 'these test files';
  return `<div class="tests-peek__note">${lead} ${files} loaded, before any of their tests:</div>${renderIds(loading)}`;
}

function renderPeek({ tests, loading }: LineContexts): string {
  if (tests.length === 0) {
    const note = loading.length === 0
      ? '<div class="tests-peek__note">It ran outside any test: at load time, in suite setup, or from a helper.</div>'
      : renderLoading(loading, false);
    return `<div class="tests-peek__title">No recorded test covers this line</div>${note}`;
  }
  const title = tests.length === 1 ? 'Covered by 1 test' : `Covered by ${tests.length} tests`;
  return `<div class="tests-peek__title">${title}</div>${renderIds(tests)}${renderLoading(loading, true)}`;
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
  const contexts = resolve(table.id, lineNumber);
  if (!contexts) return;

  const peek = document.createElement('li');
  peek.className = 'tests-peek';
  peek.innerHTML = renderPeek(contexts);
  line.after(peek);

  badge.setAttribute('aria-expanded', 'true');
  openPeek = peek;
  openBadge = badge;
}

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
    if (openPeek.contains(target) || openBadge!.contains(target)) return;
    closeTestsPeek();
  }, true);
}
