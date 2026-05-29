// Keyboard navigation of the file list: tracks the focused row and moves /
// opens it. The focused-row state lives here and nowhere else.

import { getVisibleFileRows } from './file_rows';

let focusedRow: HTMLElement | null = null;

export function hasFocusedRow(): boolean {
  return focusedRow !== null;
}

export function setFocusedRow(row: HTMLElement | null): void {
  if (focusedRow) focusedRow.classList.remove('keyboard-focus');
  focusedRow = row;
  if (focusedRow) {
    focusedRow.classList.add('keyboard-focus');
    focusedRow.scrollIntoView({ block: 'nearest' });
  }
}

export function moveFocus(direction: 1 | -1): void {
  const rows = getVisibleFileRows();
  if (!rows.length) return;
  if (!focusedRow || rows.indexOf(focusedRow) === -1) {
    setFocusedRow(direction === 1 ? rows[0] : rows[rows.length - 1]);
    return;
  }
  const idx = rows.indexOf(focusedRow) + direction;
  if (idx >= 0 && idx < rows.length) setFocusedRow(rows[idx]);
}

export function openFocusedRow(): void {
  if (!focusedRow) return;
  const link = focusedRow.querySelector('a.src_link');
  if (link) window.location.hash = link.getAttribute('href')!.substring(1);
}
