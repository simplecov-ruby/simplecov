// The modal source-file dialog and hash-based routing between the file list
// and individual source views. Owns the dialog DOM references; exposes small
// accessors so sibling modules (events, controls) can read them.

import { $$ } from './dom';
import { materializeSourceFile } from './page';
import { setFocusedRow } from './navigation';
import { invalidateFileRowCache } from './file_rows';
import { scheduleEqualizeBarWidths } from './bar_width';

let dialog: HTMLDialogElement;
let dialogBody: HTMLElement;
let dialogTitle: HTMLElement;
let activeSourceEl: HTMLElement | null = null;
let savedHeaderHTML = '';

export function dialogIsOpen(): boolean {
  return dialog.open;
}

export function getDialogBody(): HTMLElement {
  return dialogBody;
}

function restoreActiveSource(): void {
  if (!activeSourceEl) return;
  if (savedHeaderHTML) {
    activeSourceEl.insertAdjacentHTML('afterbegin', savedHeaderHTML);
    savedHeaderHTML = '';
  }
  const container = document.querySelector('.source_files');
  if (container) container.appendChild(activeSourceEl);
  activeSourceEl = null;
}

function openSourceFile(sourceFileId: string, linenumber?: string): void {
  restoreActiveSource();

  const el = materializeSourceFile(sourceFileId);
  if (!el) return;

  const header = el.querySelector('.header');
  if (header) {
    savedHeaderHTML = header.outerHTML;
    dialogTitle.innerHTML = header.innerHTML;
    header.remove();
  }

  activeSourceEl = el;
  dialogBody.appendChild(el);

  if (!dialog.open) dialog.showModal();
  document.documentElement.style.overflow = 'hidden';
  dialogBody.focus();

  if (linenumber) {
    const targetLine = dialogBody.querySelector('li[data-linenumber="' + linenumber + '"]') as HTMLElement | null;
    if (targetLine) dialogBody.scrollTop = targetLine.offsetTop;
  }
}

function showFileList(tabId: string): void {
  setFocusedRow(null);
  invalidateFileRowCache();

  if (dialog.open) {
    restoreActiveSource();
    dialog.close();
    dialogBody.innerHTML = '';
    dialogTitle.innerHTML = '';
    document.documentElement.style.overflow = '';
  }

  if (tabId) {
    const tab = document.querySelector('.group_tabs a.' + tabId);
    if (tab) {
      $$('.group_tabs li').forEach(li => li.classList.remove('active'));
      tab.parentElement!.classList.add('active');
      $$('.file_list_container').forEach(c => (c as HTMLElement).style.display = 'none');
      const target = document.getElementById(tabId);
      if (target) target.style.display = '';
    }
  }
  const wrapper = document.getElementById('wrapper');
  if (wrapper && !wrapper.classList.contains('hide')) {
    scheduleEqualizeBarWidths();
  }
}

export function navigateToHash(): void {
  const hash = window.location.hash.substring(1);

  if (!hash) {
    const firstTab = document.querySelector('.group_tabs a');
    if (firstTab) showFileList(firstTab.getAttribute('href')!.replace('#', ''));
    return;
  }

  if (hash.charAt(0) === '_') {
    showFileList(hash.substring(1));
  } else {
    const parts = hash.split('-L');
    if (!document.querySelector('.group_tabs li.active')) {
      const first = document.querySelector('.group_tabs li');
      if (first) first.classList.add('active');
    }
    openSourceFile(parts[0], parts[1]);
  }
}

export function navigateToActiveTab(): void {
  const activeLink = document.querySelector('.group_tabs li.active a');
  if (activeLink) {
    window.location.hash = activeLink.getAttribute('href')!.replace('#', '#_');
  }
}

export function setupSourceDialog(): void {
  dialog = document.getElementById('source-dialog') as HTMLDialogElement;
  dialogBody = document.getElementById('source-dialog-body')!;
  dialogTitle = document.getElementById('source-dialog-title')!;

  dialog.querySelector('.source-dialog__close')!.addEventListener('click', navigateToActiveTab);
  dialog.addEventListener('click', e => { if (e.target === dialog) navigateToActiveTab(); });
}
