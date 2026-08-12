// Exercises the bar-width equalizer's guard clauses and its binary-search
// fit. happy-dom performs no layout, so the geometry (offsetWidth,
// clientWidth, and a scrollWidth that tracks the probed bar width) is
// simulated with property getters.
import { describe, expect, test } from 'bun:test';
import { equalizeBarWidths, scheduleEqualizeBarWidths } from '../src/bar_width';

const FULL_TABLE = `
  <div class="file_list--responsive">
    <table class="file_list"><thead><tr><th><div class="bar-sizer"></div></th></tr></thead></table>
  </div>`;

function barWidth(table: HTMLElement): string {
  return table.style.getPropertyValue('--bar-sizer-width');
}

function buildContainer(inner: string): HTMLElement {
  const container = document.createElement('div');
  container.className = 'file_list_container';
  container.innerHTML = inner;
  document.body.appendChild(container);
  return container;
}

// Three bar columns share the width variable plus 200px of fixed columns,
// so the table fits its wrapper while 3 * barWidth + 200 <= clientWidth.
function stubLayout(container: HTMLElement, clientWidth: number): HTMLElement {
  Object.defineProperty(container, 'offsetWidth', { get: () => 800 });
  const wrapper = container.querySelector('.file_list--responsive') as HTMLElement;
  Object.defineProperty(wrapper, 'clientWidth', { get: () => clientWidth });
  const table = container.querySelector('table.file_list') as HTMLElement;
  Object.defineProperty(table, 'scrollWidth', {
    get: () => Number.parseInt(barWidth(table) || '160', 10) * 3 + 200
  });
  return table;
}

describe('equalizeBarWidths', () => {
  test('skips hidden, zero-width, and structurally incomplete containers', () => {
    document.body.innerHTML = '';
    const hidden = buildContainer(FULL_TABLE);
    hidden.style.display = 'none';
    const zeroWidth = buildContainer(FULL_TABLE); // offsetWidth stays 0
    const noTable = buildContainer('<div class="file_list--responsive"></div>');
    Object.defineProperty(noTable, 'offsetWidth', { get: () => 800 });
    const noSizer = buildContainer(FULL_TABLE.replace('<div class="bar-sizer"></div>', ''));
    Object.defineProperty(noSizer, 'offsetWidth', { get: () => 800 });
    const noWrapper = buildContainer(
      '<table class="file_list"><thead><tr><th><div class="bar-sizer"></div></th></tr></thead></table>'
    );
    Object.defineProperty(noWrapper, 'offsetWidth', { get: () => 800 });

    equalizeBarWidths();

    for (const container of [hidden, zeroWidth, noTable, noSizer, noWrapper]) {
      const table = container.querySelector('table');
      if (table) expect(barWidth(table as HTMLElement)).toBe('');
    }
  });

  test('binary-searches the widest bar width that fits the wrapper', () => {
    document.body.innerHTML = '';
    const container = buildContainer(FULL_TABLE);
    const table = stubLayout(container, 800); // fits while barWidth <= 200
    equalizeBarWidths();
    expect(barWidth(table)).toBe('200px');
    expect((table.closest('.file_list--responsive') as HTMLElement).style.visibility).toBe('');
  });

  test('settles on the minimum width when nothing fits', () => {
    document.body.innerHTML = '';
    const container = buildContainer(FULL_TABLE);
    const table = stubLayout(container, 0);
    equalizeBarWidths();
    expect(barWidth(table)).toBe('160px');
  });
});

describe('scheduleEqualizeBarWidths', () => {
  test('coalesces schedules into one frame and can schedule again afterwards', async () => {
    document.body.innerHTML = '';
    const container = buildContainer(FULL_TABLE);
    const table = stubLayout(container, 800);

    scheduleEqualizeBarWidths();
    scheduleEqualizeBarWidths(); // deduped while a frame is pending
    await new Promise((resolve) => requestAnimationFrame(() => resolve(undefined)));
    expect(barWidth(table)).toBe('200px');

    table.style.removeProperty('--bar-sizer-width');
    scheduleEqualizeBarWidths();
    await new Promise((resolve) => requestAnimationFrame(() => resolve(undefined)));
    expect(barWidth(table)).toBe('200px');
  });
});
