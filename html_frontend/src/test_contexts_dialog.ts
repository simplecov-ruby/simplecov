// The per-line tests dialog: lists which tests covered a given source line,
// nested above the source dialog. Data comes from page.ts's render state.

import { escapeHTML } from './dom';
import { testsCoveringLine } from './test_contexts';
import { testContextsFor } from './page';

let dialog: HTMLDialogElement;
let dialogBody: HTMLElement;
let dialogTitle: HTMLElement;

export function setupTestContextsDialog(): void {
  dialog = document.getElementById('test-contexts-dialog') as HTMLDialogElement;
  dialogBody = document.getElementById('test-contexts-dialog-body')!;
  dialogTitle = document.getElementById('test-contexts-dialog-title')!;

  dialog.querySelector('.test-contexts-dialog__close')!.addEventListener('click', closeTestContexts);
  dialog.addEventListener('click', e => { if (e.target === dialog) closeTestContexts(); });

  window.addEventListener('hashchange', closeTestContexts);
}

export function testContextsDialogIsOpen(): boolean {
  return !!dialog && dialog.open;
}

export function closeTestContexts(): void {
  if (dialog.open) dialog.close();
}

function renderTestList(indices: number[], tests: { id: string; name: string }[]): string {
  const items = indices.map(index => {
    const test = tests[index];
    const idNote = test.id === test.name ? '' : `<span class="test-contexts-dialog__id">${escapeHTML(test.id)}</span>`;
    return `<li>${escapeHTML(test.name)}${idNote}</li>`;
  }).join('');
  const noun = indices.length === 1 ? 'test' : 'tests';
  return `<p class="test-contexts-dialog__summary">Covered by ${indices.length} ${noun}:</p><ol>${items}</ol>`;
}

export function openTestContexts(sourceFileId: string, line: number): void {
  const resolved = testContextsFor(sourceFileId);
  if (!resolved) return;

  dialogTitle.textContent = `${resolved.filename}:${line}`;
  // Indices missing from the tests table (a foreign document's stray
  // key) are dropped before counting, so the summary matches the list.
  const indices = testsCoveringLine(resolved.contexts, line).filter(index => resolved.tests[index]);
  dialogBody.innerHTML = indices.length
    ? renderTestList(indices, resolved.tests)
    : '<p>No recorded test executes this line. It ran while the file was loaded, or in suite-level setup such as a before(:suite) hook.</p>';
  if (!dialog.open) dialog.showModal();
}
