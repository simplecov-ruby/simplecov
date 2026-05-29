// Dark-mode toggle and the global keyboard handler that dispatches shortcuts
// to navigation, the dialog, and missed-line jumps.

import { $, $$ } from './dom';
import { hasFocusedRow, setFocusedRow, moveFocus, openFocusedRow } from './navigation';
import { dialogIsOpen, navigateToActiveTab } from './dialog';
import { jumpToMissedLine } from './events';

// --- Dark mode ------------------------------------------------

const THEME_STORAGE_KEY = 'simplecov-dark-mode';

// localStorage can throw in locked-down contexts (Safari private mode,
// sandboxed iframes, browsers with storage disabled). The head-script
// preflight already guards against this; mirror the guard here so the
// toggle click and the prefers-color-scheme listener don't blow up.
function getThemePreference(): string | null {
  try {
    return localStorage.getItem(THEME_STORAGE_KEY);
  } catch {
    return null;
  }
}

function setThemePreference(value: string): void {
  try {
    localStorage.setItem(THEME_STORAGE_KEY, value);
  } catch {
    // No-op: same locked-down contexts as the preflight try/catch.
  }
}

export function initDarkMode(): void {
  const toggle = document.getElementById('dark-mode-toggle');
  if (!toggle) return;

  const root = document.documentElement;

  function isDark(): boolean {
    return root.classList.contains('dark-mode') ||
      (!root.classList.contains('light-mode') &&
        window.matchMedia('(prefers-color-scheme: dark)').matches);
  }

  function updateLabel(): void {
    toggle!.textContent = isDark() ? '☀️ Light' : '🌙 Dark';
  }

  updateLabel();

  toggle.addEventListener('click', () => {
    const switchToLight = isDark();
    root.classList.toggle('light-mode', switchToLight);
    root.classList.toggle('dark-mode', !switchToLight);
    setThemePreference(switchToLight ? 'light' : 'dark');
    updateLabel();
  });

  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if (!getThemePreference()) updateLabel();
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
