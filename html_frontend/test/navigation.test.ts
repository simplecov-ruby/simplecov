// Keyboard navigation of the file list: the focused-row lifecycle (focus,
// step, boundary stops, stale-row recovery) and opening the focused row via
// its source link.
import { beforeEach, describe, expect, test } from 'bun:test';
import { invalidateFileRowCache } from '../src/file_rows';
import {
  hasFocusedRow,
  moveFocus,
  openFocusedRow,
  setFocusedRow
} from '../src/navigation';

function buildRows(): HTMLElement[] {
  document.body.innerHTML = `
    <div class="file_list_container">
      <table><tbody>
        <tr class="t-file" id="row-1"><td><a class="src_link" href="#abc123-L1">a.rb</a></td></tr>
        <tr class="t-file" id="row-2"><td>no link</td></tr>
        <tr class="t-file" id="row-3"><td></td></tr>
      </tbody></table>
    </div>`;
  return ['row-1', 'row-2', 'row-3'].map((id) => document.getElementById(id)!);
}

describe('navigation', () => {
  beforeEach(() => {
    setFocusedRow(null);
    invalidateFileRowCache();
    window.location.hash = '';
  });

  test('setFocusedRow moves the keyboard-focus class between rows', () => {
    const [first, second] = buildRows();
    expect(hasFocusedRow()).toBe(false);

    setFocusedRow(first);
    expect(hasFocusedRow()).toBe(true);
    expect(first.classList.contains('keyboard-focus')).toBe(true);

    setFocusedRow(second);
    expect(first.classList.contains('keyboard-focus')).toBe(false);
    expect(second.classList.contains('keyboard-focus')).toBe(true);

    setFocusedRow(null);
    expect(hasFocusedRow()).toBe(false);
    expect(second.classList.contains('keyboard-focus')).toBe(false);
  });

  test('moveFocus is a no-op with no rows', () => {
    document.body.innerHTML = '';
    moveFocus(1);
    expect(hasFocusedRow()).toBe(false);
  });

  test('moveFocus enters the list from either end', () => {
    const rows = buildRows();
    moveFocus(1);
    expect(rows[0].classList.contains('keyboard-focus')).toBe(true);

    setFocusedRow(null);
    moveFocus(-1);
    expect(rows[2].classList.contains('keyboard-focus')).toBe(true);
  });

  test('moveFocus steps through rows and stops at the boundaries', () => {
    const rows = buildRows();
    moveFocus(1);
    moveFocus(1);
    expect(rows[1].classList.contains('keyboard-focus')).toBe(true);

    moveFocus(1);
    moveFocus(1); // already on the last row: stays put
    expect(rows[2].classList.contains('keyboard-focus')).toBe(true);

    moveFocus(-1);
    expect(rows[1].classList.contains('keyboard-focus')).toBe(true);
  });

  test('moveFocus re-enters the list when the focused row went stale', () => {
    const rows = buildRows();
    setFocusedRow(rows[1]);
    // Refiltering rebuilt the table: the focused row is no longer listed.
    rows[1].remove();
    invalidateFileRowCache();
    moveFocus(1);
    expect(rows[0].classList.contains('keyboard-focus')).toBe(true);
  });

  test('openFocusedRow follows the row link, tolerating linkless rows', () => {
    const rows = buildRows();
    openFocusedRow(); // nothing focused: no-op
    expect(window.location.hash).toBe('');

    setFocusedRow(rows[1]);
    openFocusedRow(); // focused row has no src_link
    expect(window.location.hash).toBe('');

    setFocusedRow(rows[0]);
    openFocusedRow();
    expect(window.location.hash).toBe('#abc123-L1');
  });
});
