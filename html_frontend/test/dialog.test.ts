import { afterEach, beforeEach, describe, expect, mock, spyOn, test } from 'bun:test';
import { installPageSkeleton, coverageData } from './fixture';
import { renderPage, materializeSourceFile } from '../src/page';
import { precomputeFileIds, fileId } from '../src/format';
import { setFocusedRow, hasFocusedRow } from '../src/navigation';
import { getVisibleFileRows } from '../src/file_rows';
import {
  setupSourceDialog, navigateToHash, navigateToActiveTab, dialogIsOpen, getDialogBody
} from '../src/dialog';

function clearHash(): void {
  window.location.replace(window.location.href.replace(/#.*/, ''));
}

function addTab(id: string): void {
  const li = document.createElement('li');
  li.innerHTML = `<a href="#${id}" class="${id}">All Files (100.00%)</a>`;
  document.querySelector('.group_tabs')!.appendChild(li);
}

function display(id: string): string {
  return (document.getElementById(id) as HTMLElement).style.display;
}

function activeTabs(): boolean[] {
  return Array.from(document.querySelectorAll('.group_tabs li')).map((li) => li.classList.contains('active'));
}

function open(hash: string): void {
  window.location.hash = hash;
  navigateToHash();
}

async function boot(): Promise<void> {
  installPageSkeleton();
  const data = coverageData();
  data.groups = {Libraries: {files: ['lib/covered.rb'], lines: {covered: 3, missed: 0, total: 3, percent: 100, strength: 1}}};
  await precomputeFileIds(Object.keys(data.coverage));
  renderPage(data);
  setupSourceDialog();
  addTab('g-total');
  addTab('g-group-Libraries');
  setFocusedRow(null);
  clearHash();
}

beforeEach(boot);

afterEach(() => {
  mock.restore();
});

describe('navigateToHash with an empty hash', () => {
  test('activates the first tab', () => {
    navigateToHash();
    expect(activeTabs()).toEqual([true, false]);
    expect(display('g-total')).toBe('');
    expect(display('g-group-Libraries')).toBe('none');
  });

  test('schedules a bar-width pass once the wrapper is revealed, and only then', async () => {
    await new Promise((resolve) => requestAnimationFrame(() => resolve(undefined)));
    const raf = spyOn(window, 'requestAnimationFrame').mockImplementation(() => 0);
    navigateToHash();
    expect(raf).toHaveBeenCalledTimes(0);

    document.getElementById('wrapper')!.classList.remove('hide');
    navigateToHash();
    expect(raf).toHaveBeenCalledTimes(1);

    document.getElementById('wrapper')!.remove();
    navigateToHash();
    expect(raf).toHaveBeenCalledTimes(1);
  });

  test('does nothing when no tabs exist', () => {
    document.querySelector('.group_tabs')!.innerHTML = '';
    navigateToHash();
    expect(dialogIsOpen()).toBe(false);
  });
});

describe('navigateToHash with a tab hash', () => {
  test('activates the named tab and shows only its container', () => {
    open('#_g-total');
    expect(document.querySelector('.group_tabs li.active a')!.getAttribute('href')).toBe('#g-total');
    expect(display('g-total')).toBe('');
  });

  test('moves the active marker and the visible list between tabs', () => {
    open('#_g-total');
    open('#_g-group-Libraries');
    expect(activeTabs()).toEqual([false, true]);
    expect(display('g-total')).toBe('none');
    expect(display('g-group-Libraries')).toBe('');
  });

  test('drops the focused row and the cached rows when a list is shown', () => {
    open('#_g-total');
    setFocusedRow(document.querySelector('#g-total tbody tr.t-file') as HTMLElement);
    expect(getVisibleFileRows().length).toBe(2);

    open('#_g-group-Libraries');
    expect(hasFocusedRow()).toBe(false);
    expect(getVisibleFileRows().length).toBe(1);
  });

  test('leaves the active tab alone for unknown ids', () => {
    navigateToHash();
    open('#_missing');
    expect(document.querySelector('.group_tabs li.active a')!.getAttribute('href')).toBe('#g-total');
  });

  test('tolerates an empty tab id', () => {
    navigateToHash();
    window.location.hash = '#_';
    expect(() => navigateToHash()).not.toThrow();
    expect(activeTabs()).toEqual([true, false]);
  });
});

describe('navigateToHash with a source-file hash', () => {
  test('opens the dialog on the materialized source view', () => {
    const id = fileId('lib/missed.rb');
    window.location.hash = '#' + id;
    expect(dialogIsOpen()).toBe(false);
    navigateToHash();

    expect(dialogIsOpen()).toBe(true);
    expect(activeTabs()).toEqual([true, false]);
    expect(document.getElementById('source-dialog-title')!.textContent).toContain('lib/missed.rb');
    const el = getDialogBody().querySelector('.source_table')!;
    expect(el.querySelector('.header')).toBeNull();
    expect(document.documentElement.style.overflow).toBe('hidden');
    expect(document.activeElement === getDialogBody()).toBe(true);
  });

  test('keeps the current tab active when a source file opens', () => {
    open('#_g-group-Libraries');
    open('#' + fileId('lib/covered.rb'));
    expect(activeTabs()).toEqual([false, true]);
  });

  test('scrolls to the requested line, and stays put for unknown lines', () => {
    const id = fileId('lib/missed.rb');
    const el = materializeSourceFile(id)!;
    const line = el.querySelector('li[data-linenumber="2"]') as HTMLElement;
    Object.defineProperty(line, 'offsetTop', {get: () => 77, configurable: true});

    open('#' + id + '-L2');
    expect(getDialogBody().scrollTop).toBe(77);

    open('#' + id + '-L999');
    expect(getDialogBody().scrollTop).toBe(77);
  });

  test('swaps one open source for another without reopening the dialog', () => {
    const showModal = spyOn(document.getElementById('source-dialog') as HTMLDialogElement, 'showModal');
    const covered = fileId('lib/covered.rb');
    const missed = fileId('lib/missed.rb');
    open('#' + covered);
    open('#' + missed);

    expect(showModal).toHaveBeenCalledTimes(1);
    expect(getDialogBody().querySelectorAll('.source_table').length).toBe(1);
    const restored = document.getElementById(covered)!;
    expect(document.querySelector('.source_files')!.contains(restored)).toBe(true);
    expect(restored.firstElementChild!.classList.contains('header')).toBe(true);
  });

  test('tolerates a page with no tabs', () => {
    document.querySelector('.group_tabs')!.innerHTML = '';
    open('#' + fileId('lib/covered.rb'));
    expect(dialogIsOpen()).toBe(true);
  });

  test('ignores hashes that resolve to no file', () => {
    open('#ffffffff');
    expect(dialogIsOpen()).toBe(false);
  });
});

describe('returning to the file list', () => {
  test('restores the source element and closes the dialog', () => {
    const id = fileId('lib/covered.rb');
    open('#' + id);
    expect(dialogIsOpen()).toBe(true);

    open('#_g-total');

    expect(dialogIsOpen()).toBe(false);
    const el = document.querySelector('.source_files .source_table')!;
    expect(el.id).toBe(id);
    expect(el.firstElementChild!.classList.contains('header')).toBe(true);
    expect(getDialogBody().innerHTML).toBe('');
    expect(document.getElementById('source-dialog-title')!.innerHTML).toBe('');
    expect(document.documentElement.style.overflow).toBe('');
  });

  test('restores a header-less source element as it was', () => {
    open('#' + fileId('lib/covered.rb'));
    open('#_g-total');

    const missed = fileId('lib/missed.rb');
    const el = materializeSourceFile(missed)!;
    el.querySelector('.header')!.remove();
    const before = el.innerHTML;

    open('#' + missed);
    expect(document.getElementById('source-dialog-title')!.innerHTML).toBe('');
    open('#_g-total');
    expect(el.innerHTML).toBe(before);
  });

  test('closes cleanly even when the source container is gone', () => {
    open('#' + fileId('lib/covered.rb'));
    document.querySelector('.source_files')!.remove();

    open('#_g-total');
    expect(dialogIsOpen()).toBe(false);
  });
});

describe('navigateToActiveTab', () => {
  test('jumps to the active tab and is a no-op without one', () => {
    navigateToHash();
    window.location.hash = '#somewhere';
    navigateToActiveTab();
    expect(window.location.hash).toBe('#_g-total');

    document.querySelector('.group_tabs li')!.classList.remove('active');
    window.location.hash = '#elsewhere';
    navigateToActiveTab();
    expect(window.location.hash).toBe('#elsewhere');
  });
});

describe('dialog close affordances', () => {
  test('the close button returns to the active tab', () => {
    open('#' + fileId('lib/missed.rb'));

    (document.querySelector('.source-dialog__close') as HTMLElement).click();
    expect(window.location.hash).toBe('#_g-total');
  });

  test('a backdrop click returns to the active tab; inner clicks do not', () => {
    open('#' + fileId('lib/missed.rb'));

    getDialogBody().dispatchEvent(new MouseEvent('click', {bubbles: true}));
    expect(window.location.hash).not.toBe('#_g-total');

    document.getElementById('source-dialog')!.dispatchEvent(new MouseEvent('click', {bubbles: true}));
    expect(window.location.hash).toBe('#_g-total');
  });
});
