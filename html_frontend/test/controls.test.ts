import { afterEach, beforeAll, beforeEach, describe, expect, mock, spyOn, test } from 'bun:test';
import { installPageSkeleton, coverageData } from './fixture';
import { initDarkMode, initColorblindMode, handleKeydown } from '../src/controls';
import * as page from '../src/page';
import { precomputeFileIds, fileId } from '../src/format';
import { setupSourceDialog, navigateToHash, dialogIsOpen, getDialogBody } from '../src/dialog';
import { setFocusedRow, hasFocusedRow } from '../src/navigation';
import { invalidateFileRowCache } from '../src/file_rows';
import type { CoverageData } from '../src/types';

beforeAll(() => {
  document.addEventListener('keydown', handleKeydown);
});

async function boot(customize: (data: CoverageData) => void = () => {}): Promise<void> {
  document.querySelectorAll('dialog').forEach((d) => {
    (d as HTMLDialogElement).close();
    d.remove();
  });
  installPageSkeleton();
  const data = coverageData();
  customize(data);
  await precomputeFileIds(Object.keys(data.coverage));
  page.renderPage(data);
  setupSourceDialog();
  const li = document.createElement('li');
  li.innerHTML = '<a href="#g-total" class="g-total">All Files (100.00%)</a>';
  document.querySelector('.group_tabs')!.appendChild(li);
  window.location.hash = '';
  setFocusedRow(null);
  invalidateFileRowCache();
}

function threeMissedLines(data: CoverageData): void {
  data.coverage['lib/missed.rb'].lines = [1, 0, 0, 0, 1];
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

function colorblindToggles(): HTMLElement[] {
  return Array.from(document.querySelectorAll<HTMLElement>('[data-toggle="colorblind"]'));
}

type MediaMock = {matches: boolean; queries: string[]; events: string[]; listeners: Array<() => void>};

function mockMatchMedia(matches: boolean): MediaMock {
  const media: MediaMock = {matches, queries: [], events: [], listeners: []};
  spyOn(window, 'matchMedia').mockImplementation(((query: string) => {
    media.queries.push(query);
    return {
      get matches() { return media.matches; },
      media: query,
      addEventListener: (type: string, cb: () => void) => {
        media.events.push(type);
        media.listeners.push(cb);
      }
    };
  }) as unknown as typeof window.matchMedia);
  return media;
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
    const toggles = colorblindToggles();
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

  test('reflects a palette that was applied before paint', async () => {
    await boot();
    document.documentElement.classList.add('colorblind-mode');
    initColorblindMode();
    expect(colorblindToggles().map((t) => t.getAttribute('aria-pressed'))).toEqual(['true', 'true']);
  });

  test('refreshes the favicon when the palette flips', async () => {
    await boot();
    const favicon = spyOn(page, 'updateFavicon').mockImplementation(() => {});
    initColorblindMode();
    colorblindToggles()[0].click();
    expect(favicon).toHaveBeenCalledTimes(1);
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

  test('honors an explicit light theme over a dark system preference', async () => {
    await boot();
    mockMatchMedia(true);
    document.documentElement.classList.add('light-mode');
    initDarkMode();
    expect(darkToggles()[0].textContent).toBe('🌙 Dark');
  });

  test('tracks system preference changes until a theme is chosen', async () => {
    await boot();
    const media = mockMatchMedia(false);

    initDarkMode();
    const toggle = darkToggles()[0];
    expect(toggle.textContent).toBe('🌙 Dark');
    expect(new Set(media.queries)).toEqual(new Set(['(prefers-color-scheme: dark)']));
    expect(media.events).toEqual(['change']);

    media.matches = true;
    media.listeners.forEach((cb) => cb());
    expect(toggle.textContent).toBe('☀️ Light');

    localStorage.setItem('simplecov-dark-mode', 'dark');
    media.matches = false;
    media.listeners.forEach((cb) => cb());
    expect(toggle.textContent).toBe('☀️ Light');
  });

  test('refreshes the favicon when the theme flips or the system preference changes', async () => {
    await boot();
    const media = mockMatchMedia(false);
    const favicon = spyOn(page, 'updateFavicon').mockImplementation(() => {});

    initDarkMode();
    darkToggles()[0].click();
    expect(favicon).toHaveBeenCalledTimes(1);

    media.listeners.forEach((cb) => cb());
    expect(favicon).toHaveBeenCalledTimes(2);
  });

  test('survives a locked-down localStorage', async () => {
    await boot();
    const media = mockMatchMedia(false);
    const descriptor = Object.getOwnPropertyDescriptor(window, 'localStorage')!;
    Object.defineProperty(window, 'localStorage', {
      configurable: true,
      get() {
        throw new Error('storage disabled');
      }
    });

    try {
      initDarkMode();
      darkToggles()[0].click();
      expect(document.documentElement.classList.contains('dark-mode')).toBe(true);

      media.listeners.forEach((cb) => cb());
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
    navigateToHash();
    expect(dialogIsOpen()).toBe(false);
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

    keydown(document.body, 'Escape');
    expect(hasFocusedRow()).toBe(false);
  });

  test('n/N/p jump between missed lines while the dialog is open', async () => {
    await boot(threeMissedLines);
    window.location.hash = '#' + fileId('lib/missed.rb');
    navigateToHash();
    const lines = Array.from(
      document.querySelectorAll('.source-dialog .source_table li.missed')
    ) as HTMLElement[];
    expect(lines.length).toBe(3);
    lines.forEach((line, i) => Object.defineProperty(line, 'offsetTop', {get: () => 100 * (i + 1), configurable: true}));
    const body = getDialogBody();

    expect(keydown(document.body, 'n').defaultPrevented).toBe(true);
    expect(body.scrollTop).toBe(100);
    keydown(document.body, 'n');
    expect(body.scrollTop).toBe(200);
    keydown(document.body, 'n');
    expect(body.scrollTop).toBe(300);
    expect(keydown(document.body, 'N').defaultPrevented).toBe(true);
    expect(body.scrollTop).toBe(200);
    keydown(document.body, 'p');
    expect(body.scrollTop).toBe(100);
    keydown(document.body, 'n', {shiftKey: true});
    expect(body.scrollTop).toBe(300);

    const other = keydown(document.body, 'J', {shiftKey: true});
    expect(other.defaultPrevented).toBe(false);
    expect(body.scrollTop).toBe(300);
  });

  test('j/k/Enter walk and open the file list', async () => {
    await boot();
    const rows = Array.from(document.querySelectorAll('#g-total tbody tr.t-file')) as HTMLElement[];

    expect(keydown(document.body, 'j').defaultPrevented).toBe(true);
    expect(rows[0].classList.contains('keyboard-focus')).toBe(true);
    keydown(document.body, 'j');
    expect(rows[1].classList.contains('keyboard-focus')).toBe(true);
    expect(keydown(document.body, 'k').defaultPrevented).toBe(true);
    expect(rows[0].classList.contains('keyboard-focus')).toBe(true);

    const other = keydown(document.body, 'x');
    expect(other.defaultPrevented).toBe(false);
    expect(window.location.hash).toBe('');

    const enter = keydown(document.body, 'Enter');
    expect(enter.defaultPrevented).toBe(true);
    expect(window.location.hash).toBe(rows[0].querySelector('a.src_link')!.getAttribute('href')!);
  });

  test('Enter without a focused row is left alone', async () => {
    await boot();
    const event = keydown(document.body, 'Enter');
    expect(event.defaultPrevented).toBe(false);
    expect(window.location.hash).toBe('');
  });

  test('ignores keys dispatched at the document itself', async () => {
    await boot();
    const errors: string[] = [];
    const record = (event: Event): void => { errors.push((event as ErrorEvent).message); };
    window.addEventListener('error', record);
    try {
      const event = keydown(document, 'j');
      expect(event.defaultPrevented).toBe(true);
      expect(hasFocusedRow()).toBe(true);
      expect(errors).toEqual([]);
    } finally {
      window.removeEventListener('error', record);
    }
  });

  test('list shortcuts typed inside an input are left to the input', async () => {
    await boot();
    const input = document.querySelector('#g-total .col-filter--name') as HTMLInputElement;
    input.focus();
    const event = keydown(input, 'j');
    expect(event.defaultPrevented).toBe(false);
    expect(hasFocusedRow()).toBe(false);
  });
});
