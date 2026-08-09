// Dark-mode toggle and the global keyboard handler that dispatches shortcuts
// to navigation, the dialog, and missed-line jumps.

import { $, $$ } from './dom';
import { hasFocusedRow, setFocusedRow, moveFocus, openFocusedRow } from './navigation';
import { dialogIsOpen, navigateToActiveTab } from './dialog';
import { jumpToMissedLine } from './events';
import { updateFavicon } from './page';

// --- Preferences (localStorage) -------------------------------

const THEME_STORAGE_KEY = 'simplecov-dark-mode';
const COLORBLIND_STORAGE_KEY = 'simplecov-colorblind-mode';

// localStorage can throw in locked-down contexts (Safari private mode,
// sandboxed iframes, browsers with storage disabled). The head-script
// preflight already guards against this; mirror the guard here so the
// toggle clicks and the prefers-color-scheme listener don't blow up.
function readPreference(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writePreference(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    // No-op: same locked-down contexts as the preflight try/catch.
  }
}

function getThemePreference(): string | null {
  return readPreference(THEME_STORAGE_KEY);
}

// --- Colorblind mode ------------------------------------------

// Both toggles appear twice: once in the report toolbar and once in the source
// dialog's header, so the mode can be changed from either view. They are wired
// by `data-toggle` rather than id, and every button of a kind shares one click
// handler and is kept in sync, so the two copies always agree.
function toggleButtons(kind: string): HTMLElement[] {
  return Array.from(document.querySelectorAll<HTMLElement>(`[data-toggle="${kind}"]`));
}

// A colorblind-friendly palette (blue = covered, orange = missed) plus the
// always-on coverage symbols, so red/green colour vision is never required to
// read the report. Persisted and applied before paint by the head preflight;
// this only wires the toggles. See issue #534.
export function initColorblindMode(): void {
  const toggles = toggleButtons('colorblind');
  if (toggles.length === 0) return;

  const root = document.documentElement;

  const sync = (): void => {
    const on = String(root.classList.contains('colorblind-mode'));
    toggles.forEach((t) => t.setAttribute('aria-pressed', on));
  };
  sync();

  toggles.forEach((toggle) => toggle.addEventListener('click', () => {
    const on = root.classList.toggle('colorblind-mode');
    writePreference(COLORBLIND_STORAGE_KEY, on ? 'on' : 'off');
    sync();
    updateFavicon();
  }));
}

export function initDarkMode(): void {
  const toggles = toggleButtons('dark');
  if (toggles.length === 0) return;

  const root = document.documentElement;

  function isDark(): boolean {
    return root.classList.contains('dark-mode') ||
      (!root.classList.contains('light-mode') &&
        window.matchMedia('(prefers-color-scheme: dark)').matches);
  }

  function updateLabels(): void {
    const dark = isDark();
    toggles.forEach((toggle) => {
      toggle.textContent = dark ? '☀️ Light' : '🌙 Dark';
      // This is an action button, not a toggle button: its visible label names
      // the action and flips with state, so the accessible name is kept in sync
      // with it (and contains the visible word, for WCAG 2.5.3 Label in Name).
      // No aria-pressed — that needs a stable name, which would fight the
      // flipping label. The colorblind toggle, whose label never changes, is the
      // one that carries aria-pressed.
      toggle.setAttribute('aria-label', dark ? 'Switch to light mode' : 'Switch to dark mode');
    });
  }

  updateLabels();

  toggles.forEach((toggle) => toggle.addEventListener('click', () => {
    const switchToLight = isDark();
    root.classList.toggle('light-mode', switchToLight);
    root.classList.toggle('dark-mode', !switchToLight);
    writePreference(THEME_STORAGE_KEY, switchToLight ? 'light' : 'dark');
    updateLabels();
    updateFavicon();
  }));

  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if (!getThemePreference()) updateLabels();
    updateFavicon();
  });
}

// --- Keyboard shortcuts ---------------------------------------

function focusActiveFilter(): void {
  const visible = $$('.file_list_container').filter(c => (c as HTMLElement).style.display !== 'none');
  const input = visible.length ? $('.col-filter--name', visible[0]) as HTMLElement | null : null;
  if (input) input.focus();
}

function handleEscape(e: KeyboardEvent, inInput: boolean): void {
  if (dialogIsOpen()) {
    e.preventDefault();
    navigateToActiveTab();
  } else if (inInput) {
    (e.target as HTMLElement).blur();
  } else if (hasFocusedRow()) {
    setFocusedRow(null);
  }
}

// 'n'/'N'/'p' jump between missed lines while the source dialog is open.
function handleDialogKeys(e: KeyboardEvent): void {
  if (e.key === 'n' && !e.shiftKey) { e.preventDefault(); jumpToMissedLine(1); }
  if (e.key === 'N' || (e.key === 'n' && e.shiftKey) || e.key === 'p') { e.preventDefault(); jumpToMissedLine(-1); }
}

// 'j'/'k'/'Enter' move the keyboard focus through the file list.
function handleFileListKeys(e: KeyboardEvent): void {
  if (e.key === 'j') { e.preventDefault(); moveFocus(1); }
  if (e.key === 'k') { e.preventDefault(); moveFocus(-1); }
  if (e.key === 'Enter' && hasFocusedRow()) { e.preventDefault(); openFocusedRow(); }
}

export function handleKeydown(e: KeyboardEvent): void {
  const inInput = (e.target as Element).matches('input, select, textarea');

  if (e.key === '/' && !inInput) {
    e.preventDefault();
    focusActiveFilter();
  } else if (e.key === 'Escape') {
    handleEscape(e, inInput);
  } else if (inInput) {
    // Other keys are left to the focused input.
  } else if (dialogIsOpen()) {
    handleDialogKeys(e);
  } else {
    handleFileListKeys(e);
  }
}
