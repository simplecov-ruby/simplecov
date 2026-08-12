// Delegated clicks on dynamically-materialized report content, the
// hashchange wiring, and the n/p missed-line jumps inside the dialog.
// A fresh happy-dom window is registered for this file so the document-level
// delegation is attached exactly once, whatever ran earlier in the process.
import { beforeAll, beforeEach, describe, expect, test } from 'bun:test';
import { GlobalRegistrator } from '@happy-dom/global-registrator';
import { installPageSkeleton, coverageData } from './fixture';
import { renderPage } from '../src/page';
import { precomputeFileIds, fileId } from '../src/format';
import { setupSourceDialog, navigateToHash, getDialogBody, dialogIsOpen } from '../src/dialog';
import { setupEventDelegation, jumpToMissedLine } from '../src/events';

function clearHash(): void {
  window.location.hash = '';
}

async function boot(): Promise<void> {
  // A modal left open by a previous test lives in the top layer and would
  // survive the body swap; close and remove it so stale source views can't
  // shadow the fresh ones in document-order queries.
  document.querySelectorAll('dialog').forEach((d) => {
    (d as HTMLDialogElement).close();
    d.remove();
  });
  installPageSkeleton();
  const data = coverageData();
  await precomputeFileIds(Object.keys(data.coverage));
  renderPage(data);
  setupSourceDialog();
  const li = document.createElement('li');
  li.innerHTML = '<a href="#g-total" class="g-total">All Files (100.00%)</a>';
  document.querySelector('.group_tabs')!.appendChild(li);
  clearHash();
}

function click(el: Element): void {
  el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
}

beforeAll(async () => {
  await GlobalRegistrator.unregister();
  GlobalRegistrator.register();
  setupEventDelegation();
});

beforeEach(boot);

describe('missed-method toggle', () => {
  function toggleMarkup(): string {
    return '<a href="#" class="t-missed-method-toggle">1 missed</a>' +
      '<div class="t-missed-method-list" style="display: none"><ul><li><tt>#a</tt></li></ul></div>';
  }

  test('flips the list inside a source header', () => {
    document.body.insertAdjacentHTML('beforeend', `<div class="header">${toggleMarkup()}</div>`);
    const list = document.querySelector('.t-missed-method-list') as HTMLElement;
    click(document.querySelector('.t-missed-method-toggle')!);
    expect(list.style.display).toBe('');
    click(document.querySelector('.t-missed-method-toggle')!);
    expect(list.style.display).toBe('none');
  });

  test('finds the list from the dialog title', () => {
    document.getElementById('source-dialog-title')!.innerHTML = toggleMarkup();
    click(document.querySelector('.source-dialog__title .t-missed-method-toggle')!);
    expect((document.querySelector('.source-dialog__title .t-missed-method-list') as HTMLElement).style.display).toBe('');
  });

  test('falls back to the dialog header', () => {
    document.querySelector('.source-dialog__toggles')!.insertAdjacentHTML('beforeend', toggleMarkup());
    click(document.querySelector('.source-dialog__toggles .t-missed-method-toggle')!);
    expect((document.querySelector('.source-dialog__toggles .t-missed-method-list') as HTMLElement).style.display).toBe('');
  });

  test('ignores a toggle with no recognizable parent', () => {
    document.body.insertAdjacentHTML('beforeend', toggleMarkup());
    click(document.querySelector('body > .t-missed-method-toggle')!);
    expect((document.querySelector('body > .t-missed-method-list') as HTMLElement).style.display).toBe('none');
  });
});

describe('file-list clicks', () => {
  test('a src_link click routes to the file hash', () => {
    const link = document.querySelector('#g-total a.src_link')!;
    click(link);
    expect(window.location.hash).toBe(link.getAttribute('href')!);
  });

  test('a click elsewhere in a row routes via the row link', () => {
    const row = document.querySelector('#g-total tbody tr.t-file')!;
    click(row.querySelector('td.cell--coverage')!);
    expect(window.location.hash).toBe(row.querySelector('a.src_link')!.getAttribute('href')!);
  });

  test('a row without a link goes nowhere', () => {
    const tbody = document.querySelector('#g-total tbody')!;
    const row = document.createElement('tr');
    row.className = 't-file';
    const cell = document.createElement('td');
    cell.textContent = 'plain';
    row.appendChild(cell);
    tbody.appendChild(row);
    click(cell);
    expect(window.location.hash).toBe('');
  });
});

describe('source-line clicks', () => {
  test('rewrite the hash to the clicked line and scroll to it', () => {
    const id = fileId('lib/missed.rb');
    window.location.hash = '#' + id + '-L1';
    navigateToHash();

    const line = getDialogBody().querySelector('li[data-linenumber="2"]') as HTMLElement;
    Object.defineProperty(line, 'offsetTop', {get: () => 55, configurable: true});
    click(line);

    expect(getDialogBody().scrollTop).toBe(55);
    expect(window.location.hash).toBe('#' + id + '-L2');
  });
});

describe('hashchange', () => {
  test('routes through navigateToHash', () => {
    window.location.hash = '#_g-total';
    window.dispatchEvent(new Event('hashchange'));
    expect(document.querySelector('.group_tabs li.active')).not.toBeNull();
  });
});

describe('jumpToMissedLine', () => {
  function openMissedFile(): HTMLElement[] {
    window.location.hash = '#' + fileId('lib/missed.rb');
    navigateToHash();
    // Stub layout offsets through the same query jumpToMissedLine uses, and
    // prove no stale source view shadows the fresh one.
    const lines = Array.from(
      document.querySelectorAll('.source-dialog .source_table li.missed')
    ) as HTMLElement[];
    expect(lines.length).toBe(2);
    Object.defineProperty(lines[0], 'offsetTop', {get: () => 100, configurable: true});
    Object.defineProperty(lines[1], 'offsetTop', {get: () => 200, configurable: true});
    return lines;
  }

  test('walks forward through missed lines and wraps', () => {
    openMissedFile();
    const body = getDialogBody();
    jumpToMissedLine(1);
    expect(body.scrollTop).toBe(100);
    jumpToMissedLine(1);
    expect(body.scrollTop).toBe(200);
    jumpToMissedLine(1); // nothing below → wrap to the first
    expect(body.scrollTop).toBe(100);
  });

  test('walks backward through missed lines and wraps', () => {
    openMissedFile();
    const body = getDialogBody();
    body.scrollTop = 300;
    jumpToMissedLine(-1);
    expect(body.scrollTop).toBe(200);
    jumpToMissedLine(-1);
    expect(body.scrollTop).toBe(100);
    jumpToMissedLine(-1); // nothing above 90 → wrap to the last
    expect(body.scrollTop).toBe(200);
  });

  test('does nothing without missed lines', () => {
    expect(dialogIsOpen()).toBe(false);
    jumpToMissedLine(1);
    expect(getDialogBody().scrollTop).toBe(0);
  });
});
