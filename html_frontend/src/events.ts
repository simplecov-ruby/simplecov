// Delegated click handling for dynamically-materialized source content, plus
// jumping between missed lines within the open dialog.

import { $$, on } from './dom';
import { navigateToHash, getDialogBody } from './dialog';

function getMissedLines(): HTMLElement[] {
  return $$('.source-dialog .source_table li.missed, .source-dialog .source_table li.missed-branch, .source-dialog .source_table li.missed-method') as HTMLElement[];
}

export function jumpToMissedLine(direction: 1 | -1): void {
  const lines = getMissedLines();
  if (!lines.length) return;

  const dialogBody = getDialogBody();
  const midpoint = dialogBody.scrollTop + dialogBody.clientHeight / 2;
  // The -10 bias on the backward search keeps the currently-centered line
  // from counting as its own "previous" hit when we're sitting on it.
  const target = direction === 1
    ? lines.find((li) => li.offsetTop > midpoint) || lines[0]
    : lines.findLast((li) => li.offsetTop < midpoint - 10) || lines[lines.length - 1];

  dialogBody.scrollTop = target.offsetTop - dialogBody.clientHeight / 3;
}

// Event delegation for dynamically-materialized source content.
export function setupEventDelegation(): void {
  on(document, 'click', '.t-missed-method-toggle', function (e: Event) {
    e.preventDefault();
    const parent = this.closest('.header') || this.closest('.source-dialog__title') || this.closest('.source-dialog__header');
    const list = parent ? parent.querySelector('.t-missed-method-list') as HTMLElement | null : null;
    if (list) list.style.display = list.style.display === 'none' ? '' : 'none';
  });

  on(document, 'click', 'a.src_link', function (e: Event) {
    e.preventDefault();
    window.location.hash = this.getAttribute('href')!.substring(1);
  });

  on(document, 'click', 'table.file_list tbody tr', function (e: Event) {
    if ((e.target as Element).closest('a')) return;
    const link = this.querySelector('a.src_link');
    if (link) window.location.hash = link.getAttribute('href')!.substring(1);
  });

  on(document, 'click', '.source-dialog .source_table li[data-linenumber]', function (e: Event) {
    e.preventDefault();
    getDialogBody().scrollTop = (this as HTMLElement).offsetTop;
    const linenumber = (this as HTMLElement).dataset.linenumber;
    const sourceFileId = window.location.hash.substring(1).replace(/-L.*/, '');
    window.location.replace(window.location.href.replace(/#.*/, '#' + sourceFileId + '-L' + linenumber));
  });

  window.addEventListener('hashchange', navigateToHash);
}
