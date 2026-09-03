import { afterEach, describe, expect, mock, spyOn, test } from 'bun:test';
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

function stubLayout(container: HTMLElement, clientWidth: number, probes: string[] = []): HTMLElement {
  Object.defineProperty(container, 'offsetWidth', { get: () => 800 });
  const wrapper = container.querySelector('.file_list--responsive') as HTMLElement;
  Object.defineProperty(wrapper, 'clientWidth', { get: () => clientWidth });
  const table = container.querySelector('table.file_list') as HTMLElement;
  Object.defineProperty(table, 'scrollWidth', {
    get: () => {
      probes.push(wrapper.style.visibility);
      return Number.parseInt(barWidth(table) || '160', 10) * 3 + 200;
    }
  });
  return table;
}

function nextFrame(): Promise<void> {
  return new Promise((resolve) => requestAnimationFrame(() => resolve()));
}

afterEach(() => {
  mock.restore();
});

describe('equalizeBarWidths', () => {
  test('skips hidden, zero-width, and structurally incomplete containers', () => {
    document.body.innerHTML = '';
    const hidden = buildContainer(FULL_TABLE);
    hidden.style.display = 'none';
    stubLayout(hidden, 800);
    const zeroWidth = buildContainer(FULL_TABLE);
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

  test('binary-searches the widest bar width that fits the wrapper, hiding the probes', () => {
    document.body.innerHTML = '';
    const container = buildContainer(FULL_TABLE);
    const probes: string[] = [];
    const table = stubLayout(container, 800, probes);
    equalizeBarWidths();
    expect(barWidth(table)).toBe('200px');
    expect(probes.length).toBeGreaterThan(0);
    expect(new Set(probes)).toEqual(new Set(['hidden']));
    expect((table.closest('.file_list--responsive') as HTMLElement).style.visibility).toBe('');
  });

  test('settles within a step of the widest fit', () => {
    document.body.innerHTML = '';
    const container = buildContainer(FULL_TABLE);
    const table = stubLayout(container, 698);
    equalizeBarWidths();
    expect(barWidth(table)).toBe('165px');
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
    await nextFrame();
    const raf = spyOn(window, 'requestAnimationFrame');

    scheduleEqualizeBarWidths();
    scheduleEqualizeBarWidths();
    expect(raf).toHaveBeenCalledTimes(1);
    await nextFrame();
    expect(barWidth(table)).toBe('200px');

    table.style.removeProperty('--bar-sizer-width');
    scheduleEqualizeBarWidths();
    expect(raf).toHaveBeenCalledTimes(3);
    await nextFrame();
    expect(barWidth(table)).toBe('200px');
  });
});
