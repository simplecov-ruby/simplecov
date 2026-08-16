// The per-line tests dialog: opening from render state, escaped names,
// the load-only explanation, and close interactions.
import { describe, expect, test } from 'bun:test';
import { installPageSkeleton, coverageData } from './fixture';
import { renderPage } from '../src/page';
import { precomputeFileIds, fileId } from '../src/format';
import {
  setupTestContextsDialog, openTestContexts, closeTestContexts, testContextsDialogIsOpen
} from '../src/test_contexts_dialog';
import type { CoverageData } from '../src/types';

function contextsData(): CoverageData {
  const data = coverageData();
  data.meta.test_contexts = {
    granularity: 'per_test',
    tests: [
      {id: './spec/covered_spec.rb[1:1]', name: 'covers <em>everything</em>'},
      {id: 'CoveredTest#test_covered', name: 'CoveredTest#test_covered'}
    ]
  };
  // test 0 covers lines 1-2, test 1 covers line 2; missed.rb ran only in setup
  data.coverage['lib/covered.rb'].test_contexts = {'0': '3', '1': '2'};
  data.coverage['lib/missed.rb'].test_contexts = {};
  return data;
}

async function boot(data = contextsData()): Promise<void> {
  document.querySelectorAll('dialog').forEach((d) => {
    (d as HTMLDialogElement).close();
    d.remove();
  });
  installPageSkeleton();
  await precomputeFileIds(Object.keys(data.coverage));
  renderPage(data);
  setupTestContextsDialog();
}

function dialogBody(): HTMLElement {
  return document.getElementById('test-contexts-dialog-body')!;
}

describe('openTestContexts', () => {
  test('lists the covering tests with escaped names and rerun ids', async () => {
    await boot();
    openTestContexts(fileId('lib/covered.rb'), 2);

    expect(testContextsDialogIsOpen()).toBe(true);
    expect(document.getElementById('test-contexts-dialog-title')!.textContent).toBe('lib/covered.rb:2');
    expect(dialogBody().textContent).toContain('Covered by 2 tests:');
    expect(dialogBody().innerHTML).toContain('covers &lt;em&gt;everything&lt;/em&gt;');
    expect(dialogBody().innerHTML).toContain('./spec/covered_spec.rb[1:1]');
    // An entry whose id equals its name is not repeated below itself.
    expect(dialogBody().querySelectorAll('.test-contexts-dialog__id').length).toBe(1);
  });

  test('uses the singular for one covering test', async () => {
    await boot();
    openTestContexts(fileId('lib/covered.rb'), 1);

    expect(dialogBody().textContent).toContain('Covered by 1 test:');
  });

  test('treats indices missing from the table as no recorded test, keeping count and list in step', async () => {
    const data = contextsData();
    data.coverage['lib/covered.rb'].test_contexts = {'9': '2'};
    await boot(data);
    openTestContexts(fileId('lib/covered.rb'), 2);

    expect(dialogBody().querySelectorAll('li').length).toBe(0);
    expect(dialogBody().textContent).not.toContain('Covered by');
    expect(dialogBody().textContent).toContain('No recorded test executes this line');
  });

  test('explains a line no recorded test covers', async () => {
    await boot();
    openTestContexts(fileId('lib/missed.rb'), 1);

    expect(testContextsDialogIsOpen()).toBe(true);
    expect(dialogBody().textContent).toContain('No recorded test executes this line');
  });

  test('does nothing without recorded contexts', async () => {
    await boot(coverageData());
    openTestContexts(fileId('lib/covered.rb'), 1);

    expect(testContextsDialogIsOpen()).toBe(false);
  });

  test('does nothing for an unknown file id', async () => {
    await boot();
    openTestContexts('no-such-id', 1);

    expect(testContextsDialogIsOpen()).toBe(false);
  });

  test('does nothing for a file that carries no contexts', async () => {
    const data = contextsData();
    delete data.coverage['lib/missed.rb'].test_contexts;
    await boot(data);
    openTestContexts(fileId('lib/missed.rb'), 1);

    expect(testContextsDialogIsOpen()).toBe(false);
  });
});

describe('closing', () => {
  test('the close button closes the dialog', async () => {
    await boot();
    openTestContexts(fileId('lib/covered.rb'), 1);

    (document.querySelector('.test-contexts-dialog__close') as HTMLElement).click();

    expect(testContextsDialogIsOpen()).toBe(false);
  });

  test('a backdrop click closes the dialog', async () => {
    await boot();
    openTestContexts(fileId('lib/covered.rb'), 1);

    document.getElementById('test-contexts-dialog')!
      .dispatchEvent(new MouseEvent('click', {bubbles: true}));

    expect(testContextsDialogIsOpen()).toBe(false);
  });

  test('closeTestContexts tolerates an already-closed dialog', async () => {
    await boot();
    closeTestContexts();

    expect(testContextsDialogIsOpen()).toBe(false);
  });

  test('a hash change closes the dialog instead of orphaning it over the next view', async () => {
    await boot();
    openTestContexts(fileId('lib/covered.rb'), 1);
    expect(testContextsDialogIsOpen()).toBe(true);

    window.dispatchEvent(new Event('hashchange'));

    expect(testContextsDialogIsOpen()).toBe(false);
  });
});
