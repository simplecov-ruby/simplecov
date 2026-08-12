// Hash-based routing between the file list and the modal source dialog:
// tab activation, on-demand source materialization into the dialog, header
// save/restore, and the close affordances.
import { beforeEach, describe, expect, test } from 'bun:test';
import { installPageSkeleton, coverageData } from './fixture';
import { renderPage, materializeSourceFile } from '../src/page';
import { precomputeFileIds, fileId } from '../src/format';
import {
  setupSourceDialog, navigateToHash, navigateToActiveTab, dialogIsOpen, getDialogBody
} from '../src/dialog';

function clearHash(): void {
  window.location.replace(window.location.href.replace(/#.*/, ''));
}

// What app.ts's setupTabs builds, reduced to what dialog.ts reads.
function addTab(id: string): void {
  const li = document.createElement('li');
  li.innerHTML = `<a href="#${id}" class="${id}">All Files (100.00%)</a>`;
  document.querySelector('.group_tabs')!.appendChild(li);
}

async function boot(): Promise<void> {
  installPageSkeleton();
  const data = coverageData();
  await precomputeFileIds(Object.keys(data.coverage));
  renderPage(data);
  setupSourceDialog();
  addTab('g-total');
  clearHash();
}

beforeEach(boot);

describe('navigateToHash with an empty hash', () => {
  test('activates the first tab', () => {
    navigateToHash();
    expect(document.querySelector('.group_tabs li')!.classList.contains('active')).toBe(true);
    expect((document.getElementById('g-total') as HTMLElement).style.display).toBe('');
  });

  test('schedules a bar-width pass once the wrapper is revealed', () => {
    document.getElementById('wrapper')!.classList.remove('hide');
    navigateToHash();
    expect(document.querySelector('.group_tabs li.active')).not.toBeNull();
  });

  test('does nothing when no tabs exist', () => {
    document.querySelector('.group_tabs')!.innerHTML = '';
    navigateToHash();
    expect(dialogIsOpen()).toBe(false);
  });
});

describe('navigateToHash with a tab hash', () => {
  test('activates the named tab and shows only its container', () => {
    window.location.hash = '#_g-total';
    navigateToHash();
    expect(document.querySelector('.group_tabs li.active a')!.getAttribute('href')).toBe('#g-total');
    expect((document.getElementById('g-total') as HTMLElement).style.display).toBe('');
  });

  test('leaves the active tab alone for unknown ids', () => {
    navigateToHash(); // activates g-total
    window.location.hash = '#_missing';
    navigateToHash();
    expect(document.querySelector('.group_tabs li.active a')!.getAttribute('href')).toBe('#g-total');
  });
});

describe('navigateToHash with a source-file hash', () => {
  test('opens the dialog on the materialized source view', () => {
    const id = fileId('lib/missed.rb');
    window.location.hash = '#' + id;
    expect(dialogIsOpen()).toBe(false);
    navigateToHash();

    expect(dialogIsOpen()).toBe(true);
    // No tab was active, so the first one is marked active for the return trip.
    expect(document.querySelector('.group_tabs li')!.classList.contains('active')).toBe(true);
    expect(document.getElementById('source-dialog-title')!.textContent).toContain('lib/missed.rb');
    // The header moved out of the source element into the dialog title.
    const el = getDialogBody().querySelector('.source_table')!;
    expect(el.querySelector('.header')).toBeNull();
    expect(document.documentElement.style.overflow).toBe('hidden');
  });

  test('scrolls to the requested line, and stays put for unknown lines', () => {
    const id = fileId('lib/missed.rb');
    const el = materializeSourceFile(id)!;
    const line = el.querySelector('li[data-linenumber="2"]') as HTMLElement;
    Object.defineProperty(line, 'offsetTop', {get: () => 77, configurable: true});

    window.location.hash = '#' + id + '-L2';
    navigateToHash();
    expect(getDialogBody().scrollTop).toBe(77);

    // Re-navigating while open (no showModal) to a line that does not exist.
    window.location.hash = '#' + id + '-L999';
    navigateToHash();
    expect(getDialogBody().scrollTop).toBe(77);
  });

  test('tolerates a page with no tabs', () => {
    document.querySelector('.group_tabs')!.innerHTML = '';
    window.location.hash = '#' + fileId('lib/covered.rb');
    navigateToHash();
    expect(dialogIsOpen()).toBe(true);
  });

  test('ignores hashes that resolve to no file', () => {
    window.location.hash = '#ffffffff';
    navigateToHash();
    expect(dialogIsOpen()).toBe(false);
  });
});

describe('returning to the file list', () => {
  test('restores the source element and closes the dialog', () => {
    const id = fileId('lib/covered.rb');
    window.location.hash = '#' + id;
    navigateToHash();
    expect(dialogIsOpen()).toBe(true);

    window.location.hash = '#_g-total';
    navigateToHash();

    expect(dialogIsOpen()).toBe(false);
    const el = document.querySelector('.source_files .source_table')!;
    expect(el.id).toBe(id);
    // The saved header was reinserted at the top of the source element.
    expect(el.firstElementChild!.classList.contains('header')).toBe(true);
    expect(getDialogBody().innerHTML).toBe('');
    expect(document.getElementById('source-dialog-title')!.innerHTML).toBe('');
    expect(document.documentElement.style.overflow).toBe('');
  });

  test('closes cleanly even when the source container is gone', () => {
    window.location.hash = '#' + fileId('lib/covered.rb');
    navigateToHash();
    document.querySelector('.source_files')!.remove();

    window.location.hash = '#_g-total';
    navigateToHash();
    expect(dialogIsOpen()).toBe(false);
  });
});

describe('navigateToActiveTab', () => {
  test('jumps to the active tab and is a no-op without one', () => {
    navigateToHash(); // activates g-total
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
    window.location.hash = '#' + fileId('lib/missed.rb');
    navigateToHash();

    (document.querySelector('.source-dialog__close') as HTMLElement).click();
    expect(window.location.hash).toBe('#_g-total');
  });

  test('a backdrop click returns to the active tab; inner clicks do not', () => {
    window.location.hash = '#' + fileId('lib/missed.rb');
    navigateToHash();

    getDialogBody().dispatchEvent(new MouseEvent('click', {bubbles: true}));
    expect(window.location.hash).not.toBe('#_g-total');

    document.getElementById('source-dialog')!.dispatchEvent(new MouseEvent('click', {bubbles: true}));
    expect(window.location.hash).toBe('#_g-total');
  });
});
