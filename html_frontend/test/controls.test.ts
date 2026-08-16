// Theme and colorblind toggles (persistence, paired-button sync, system
// preference tracking) and the global keyboard dispatch for filter focus,
// escape, dialog jumps, and file-list navigation.
import { afterEach, beforeAll, beforeEach, describe, expect, mock, spyOn, test } from 'bun:test';
import { installPageSkeleton, coverageData, coverageDataWithContexts } from './fixture';
import { initDarkMode, initColorblindMode, handleKeydown } from '../src/controls';
import { renderPage } from '../src/page';
import { precomputeFileIds, fileId } from '../src/format';
import { setupSourceDialog, navigateToHash, dialogIsOpen, getDialogBody } from '../src/dialog';
import { setupTestContextsDialog, openTestContexts, testContextsDialogIsOpen } from '../src/test_contexts_dialog';
import { setFocusedRow, hasFocusedRow } from '../src/navigation';
import { invalidateFileRowCache } from '../src/file_rows';

beforeAll(() => {
  // Same listener wiring as app.ts; EventTarget dedupes the shared function
  // reference if another suite already added it.
  document.addEventListener('keydown', handleKeydown);
});

async function boot(): Promise<void> {
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
  window.location.hash = '';
  setFocusedRow(null);
  invalidateFileRowCache();
}

beforeEach(() => {
  document.documentElement.className = '';
});

afterEach(() => {
  mock.restore();
  localStorage.clear();
});

function keydown(target: EventTarget, key: string, init: KeyboardEventInit = {}): KeyboardEvent {
  const event = new KeyboardEvent('keydown', {key, bubbles: true, cancelable: true, ...init});
  target.dispatchEvent(event);
  return event;
}

function darkToggles(): HTMLElement[] {
  return Array.from(document.querySelectorAll<HTMLElement>('[data-toggle="dark"]'));
}

describe('initColorblindMode', () => {
  test('does nothing on a page without toggles', () => {
    document.body.innerHTML = '';
    initColorblindMode();
    expect(document.documentElement.classList.contains('colorblind-mode')).toBe(false);
  });

  test('keeps both toggle copies and the preference in sync', async () => {
    await boot();
    initColorblindMode();
    const toggles = Array.from(document.querySelectorAll<HTMLElement>('[data-toggle="colorblind"]'));
    expect(toggles.length).toBe(2);
    expect(toggles.map((t) => t.getAttribute('aria-pressed'))).toEqual(['false', 'false']);

    toggles[0].click();
    expect(document.documentElement.classList.contains('colorblind-mode')).toBe(true);
    expect(localStorage.getItem('simplecov-colorblind-mode')).toBe('on');
    expect(toggles.map((t) => t.getAttribute('aria-pressed'))).toEqual(['true', 'true']);

    toggles[1].click();
    expect(document.documentElement.classList.contains('colorblind-mode')).toBe(false);
    expect(localStorage.getItem('simplecov-colorblind-mode')).toBe('off');
  });
});

describe('initDarkMode', () => {
  test('does nothing on a page without toggles', () => {
    document.body.innerHTML = '';
    initDarkMode();
    expect(document.documentElement.classList.contains('dark-mode')).toBe(false);
  });

  test('labels the action and flips the theme on click', async () => {
    await boot();
    initDarkMode();
    const toggles = darkToggles();
    // happy-dom's prefers-color-scheme never matches, so the page starts light.
    expect(toggles[0].textContent).toBe('🌙 Dark');
    expect(toggles[0].getAttribute('aria-label')).toBe('Switch to dark mode');

    toggles[0].click();
    expect(document.documentElement.classList.contains('dark-mode')).toBe(true);
    expect(localStorage.getItem('simplecov-dark-mode')).toBe('dark');
    expect(toggles.map((t) => t.textContent)).toEqual(['☀️ Light', '☀️ Light']);
    expect(toggles[1].getAttribute('aria-label')).toBe('Switch to light mode');

    toggles[0].click();
    expect(document.documentElement.classList.contains('light-mode')).toBe(true);
    expect(document.documentElement.classList.contains('dark-mode')).toBe(false);
    expect(localStorage.getItem('simplecov-dark-mode')).toBe('light');
    expect(toggles[0].textContent).toBe('🌙 Dark');
  });

  test('tracks system preference changes until a theme is chosen', async () => {
    await boot();
    const changeListeners: Array<() => void> = [];
    spyOn(window, 'matchMedia').mockImplementation(((query: string) => ({
      matches: true,
      media: query,
      addEventListener: (_type: string, cb: () => void) => changeListeners.push(cb)
    })) as unknown as typeof window.matchMedia);

    initDarkMode();
    const toggle = darkToggles()[0];
    // No stored theme, system prefers dark → the action offers light mode.
    expect(toggle.textContent).toBe('☀️ Light');

    changeListeners.forEach((cb) => cb());
    expect(toggle.textContent).toBe('☀️ Light');

    // With an explicit choice stored, the change handler leaves labels alone.
    localStorage.setItem('simplecov-dark-mode', 'dark');
    changeListeners.forEach((cb) => cb());
    expect(toggle.textContent).toBe('☀️ Light');
  });

  test('survives a locked-down localStorage', async () => {
    await boot();
    const changeListeners: Array<() => void> = [];
    spyOn(window, 'matchMedia').mockImplementation(((query: string) => ({
      matches: false,
      media: query,
      addEventListener: (_type: string, cb: () => void) => changeListeners.push(cb)
    })) as unknown as typeof window.matchMedia);
    // happy-dom's Storage is a Proxy that shrugs off method spies, but the
    // window.localStorage accessor is configurable — locked-down browsers
    // throw on the access itself, which is exactly the guarded scenario.
    const descriptor = Object.getOwnPropertyDescriptor(window, 'localStorage')!;
    Object.defineProperty(window, 'localStorage', {
      configurable: true,
      get() {
        throw new Error('storage disabled');
      }
    });

    try {
      initDarkMode();
      darkToggles()[0].click(); // writePreference swallows the throw
      expect(document.documentElement.classList.contains('dark-mode')).toBe(true);

      changeListeners.forEach((cb) => cb()); // readPreference swallows the throw
      expect(darkToggles()[0].textContent).toBe('☀️ Light');
    } finally {
      Object.defineProperty(window, 'localStorage', descriptor);
    }
  });
});

describe('handleKeydown', () => {
  test('"/" focuses the visible file filter', async () => {
    await boot();
    const event = keydown(document.body, '/');
    expect(event.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(document.querySelector('#g-total .col-filter--name'));
  });

  test('"/" without a visible file list does nothing', async () => {
    await boot();
    document.querySelectorAll('.file_list_container').forEach((c) => {
      (c as HTMLElement).style.display = 'none';
    });
    const event = keydown(document.body, '/');
    expect(event.defaultPrevented).toBe(true);
    expect(document.activeElement).not.toBeInstanceOf(HTMLInputElement);
  });

  test('"/" typed inside an input is left to the input', async () => {
    await boot();
    const input = document.querySelector('#g-total .col-filter--name') as HTMLInputElement;
    input.focus();
    const event = keydown(input, '/');
    expect(event.defaultPrevented).toBe(false);
    expect(document.activeElement).toBe(input);
  });

  test('Escape closes the dialog via the active tab', async () => {
    await boot();
    window.location.hash = '#' + fileId('lib/covered.rb');
    navigateToHash();
    expect(dialogIsOpen()).toBe(true);

    const event = keydown(document.body, 'Escape');
    expect(event.defaultPrevented).toBe(true);
    expect(window.location.hash).toBe('#_g-total');
    navigateToHash(); // actually close, as the hashchange listener would
    expect(dialogIsOpen()).toBe(false);
  });

  test('Escape closes the nested tests dialog first, then the source dialog', async () => {
    await boot();
    renderPage(coverageDataWithContexts());
    setupTestContextsDialog();

    window.location.hash = '#' + fileId('lib/covered.rb');
    navigateToHash();
    expect(dialogIsOpen()).toBe(true);
    openTestContexts(fileId('lib/covered.rb'), 1);
    expect(testContextsDialogIsOpen()).toBe(true);

    const first = keydown(document.body, 'Escape');
    expect(first.defaultPrevented).toBe(true);
    expect(testContextsDialogIsOpen()).toBe(false);
    expect(dialogIsOpen()).toBe(true);

    keydown(document.body, 'Escape');
    expect(window.location.hash).toBe('#_g-total');
  });

  test("'n' does not act on the source dialog beneath the open tests dialog", async () => {
    await boot();
    renderPage(coverageDataWithContexts());
    setupTestContextsDialog();

    window.location.hash = '#' + fileId('lib/covered.rb');
    navigateToHash();
    openTestContexts(fileId('lib/covered.rb'), 1);
    expect(testContextsDialogIsOpen()).toBe(true);

    const event = keydown(document.body, 'n');
    expect(event.defaultPrevented).toBe(false);
    expect(testContextsDialogIsOpen()).toBe(true);
  });

  test('Escape blurs a focused input', async () => {
    await boot();
    const input = document.querySelector('#g-total .col-filter--name') as HTMLInputElement;
    input.focus();
    keydown(input, 'Escape');
    expect(document.activeElement).not.toBe(input);
  });

  test('Escape clears the focused row, then falls through', async () => {
    await boot();
    const row = document.querySelector('#g-total tbody tr.t-file') as HTMLElement;
    setFocusedRow(row);
    keydown(document.body, 'Escape');
    expect(hasFocusedRow()).toBe(false);
    expect(row.classList.contains('keyboard-focus')).toBe(false);

    keydown(document.body, 'Escape'); // nothing left to escape from
    expect(hasFocusedRow()).toBe(false);
  });

  test('n/N/p jump between missed lines while the dialog is open', async () => {
    await boot();
    window.location.hash = '#' + fileId('lib/missed.rb');
    navigateToHash();
    const lines = Array.from(
      document.querySelectorAll('.source-dialog .source_table li.missed')
    ) as HTMLElement[];
    expect(lines.length).toBe(2);
    Object.defineProperty(lines[0], 'offsetTop', {get: () => 100, configurable: true});
    Object.defineProperty(lines[1], 'offsetTop', {get: () => 200, configurable: true});
    const body = getDialogBody();

    keydown(document.body, 'n');
    expect(body.scrollTop).toBe(100);
    keydown(document.body, 'n');
    expect(body.scrollTop).toBe(200);
    keydown(document.body, 'p');
    expect(body.scrollTop).toBe(100);
    keydown(document.body, 'N');
    expect(body.scrollTop).toBe(200); // nothing above → wrapped to the last
    keydown(document.body, 'n', {shiftKey: true});
    expect(body.scrollTop).toBe(100);
  });

  test('j/k/Enter walk and open the file list', async () => {
    await boot();
    const rows = Array.from(document.querySelectorAll('#g-total tbody tr.t-file')) as HTMLElement[];

    keydown(document.body, 'j');
    expect(rows[0].classList.contains('keyboard-focus')).toBe(true);
    keydown(document.body, 'j');
    expect(rows[1].classList.contains('keyboard-focus')).toBe(true);
    keydown(document.body, 'k');
    expect(rows[0].classList.contains('keyboard-focus')).toBe(true);

    keydown(document.body, 'Enter');
    expect(window.location.hash).toBe(rows[0].querySelector('a.src_link')!.getAttribute('href')!);
  });

  test('Enter without a focused row does nothing', async () => {
    await boot();
    keydown(document.body, 'Enter');
    expect(window.location.hash).toBe('');
  });
});
