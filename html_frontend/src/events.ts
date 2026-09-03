
import { $$, on } from './dom';
import { navigateToHash, getDialogBody } from './dialog';
import { contextsForSourceLine } from './page';
import { toggleTestsPeek, setupTestsPeekDismissal } from './tests_peek';

function getMissedLines(): HTMLElement[] {
  return $$('.source-dialog .source_table li.missed, .source-dialog .source_table li.missed-branch, .source-dialog .source_table li.missed-method') as HTMLElement[];
}

export function jumpToMissedLine(direction: 1 | -1): void {
  const lines = getMissedLines();
  if (!lines.length) return;

  const dialogBody = getDialogBody();
  const midpoint = dialogBody.scrollTop + dialogBody.clientHeight / 2;
  const target = direction === 1
    ? lines.find((li) => li.offsetTop > midpoint) || lines[0]
    : lines.findLast((li) => li.offsetTop < midpoint - 10) || lines[lines.length - 1];

  dialogBody.scrollTop = target.offsetTop - dialogBody.clientHeight / 3;
}

export function setupEventDelegation(): void {
  on(document, 'click', '.t-missed-method-toggle', function (e: Event) {
    e.preventDefault();
    const parent = this.closest('.header') || this.closest('.source-dialog__title') || this.closest('.source-dialog__header');
    const list = parent ? parent.querySelector('.t-missed-method-list') as HTMLElement | null : null;
    if (list) list.style.display = list.style.display === 'none' ? '' : 'none';
  });

  on(document, 'click', 'table.file_list tbody tr', function () {
    const link = this.querySelector('a.src_link');
    if (link) window.location.hash = link.getAttribute('href')!;
  });

  on(document, 'click', 'button.hits--tests', function (e: Event) {
    e.preventDefault();
    toggleTestsPeek(this as HTMLElement, contextsForSourceLine);
  });

  on(document, 'click', '.source-dialog .source_table li[data-linenumber]', function (e: Event) {
    if ((e.target as Element).closest('.hits--tests, .tests-peek')) return;
    e.preventDefault();
    getDialogBody().scrollTop = (this as HTMLElement).offsetTop;
    const linenumber = (this as HTMLElement).dataset.linenumber;
    const sourceFileId = window.location.hash.substring(1).replace(/-L.*/, '');
    window.location.replace(window.location.href.replace(/#.*/, '#' + sourceFileId + '-L' + linenumber));
  });

  window.addEventListener('hashchange', navigateToHash);
  setupTestsPeekDismissal();
}
