import { afterAll, afterEach, beforeAll, describe, expect, mock, spyOn, test } from 'bun:test';
import { GlobalRegistrator } from '@happy-dom/global-registrator';
import { coverageData, installPageSkeleton } from './fixture';
import { precomputeFileIds, fileId } from '../src/format';
import type { CoverageData } from '../src/types';
import { scheduleTimeago } from '../src/app';

afterAll(async () => {
  window.location.hash = '';
  await new Promise((resolve) => setTimeout(resolve, 0));
  await nextFrame();
  await nextFrame();
  await GlobalRegistrator.unregister();
  GlobalRegistrator.register();
});

afterEach(() => {
  mock.restore();
  localStorage.clear();
});

function bodyText(selector: string): string {
  const el = document.querySelector(selector);
  return el ? el.textContent || '' : '';
}

function display(id: string): string {
  return (document.getElementById(id) as HTMLElement).style.display;
}

async function until(check: () => boolean): Promise<void> {
  for (let i = 0; i < 200; i++) {
    if (check()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error('condition never became true');
}

function embeddedData(): CoverageData {
  const data = coverageData();
  data.groups = {Libraries: {files: ['lib/covered.rb'], lines: {covered: 3, missed: 0, total: 3, percent: 100, strength: 1}}};
  data.meta.timestamp = new Date(Date.now() - 10 * 3600 * 1000).toISOString();
  return data;
}

async function prepareBoot(hash: string): Promise<void> {
  window.location.hash = hash;
  installPageSkeleton();
  await nextFrame();
  await nextFrame();
}

function startBoot(): void {
  window.SIMPLECOV_DATA = embeddedData();
  document.dispatchEvent(new Event('DOMContentLoaded'));
}

async function boot(hash = ''): Promise<void> {
  await prepareBoot(hash);
  startBoot();
  await until(() => bodyText('#footer').includes('simplecov'));
}

function nextFrame(): Promise<void> {
  return new Promise((resolve) => requestAnimationFrame(() => resolve()));
}

describe('application boot', () => {
  beforeAll(() => boot());

  test('renders the file lists and footer from the embedded data', () => {
    expect(document.title).toBe('Code coverage for Sample Project');
    expect(bodyText('#g-total')).toContain('lib/covered.rb');
    expect(bodyText('#g-total')).toContain('lib/missed.rb');
    expect(bodyText('#footer')).toContain('using RSpec');
  });

  test('builds one tab per group and shows the All Files tab first', () => {
    const tabs = Array.from(document.querySelectorAll('.group_tabs a'));
    expect(tabs.map((tab) => tab.getAttribute('href'))).toEqual(['#g-total', '#g-group-Libraries']);
    expect(display('g-total')).toBe('');
    expect(display('g-group-Libraries')).toBe('none');
  });

  test('labels each tab with its group name and coverage', () => {
    const tabs = Array.from(document.querySelectorAll('.group_tabs li'));
    expect(tabs.map((li) => li.getAttribute('role'))).toEqual(['tab', 'tab']);
    expect(tabs.map((li) => li.textContent)).toEqual(['All Files (71.42%)', 'Libraries (100.00%)']);
  });

  test('switches groups when a tab is clicked', async () => {
    const groupTab = document.querySelector('.group_tabs a.g-group-Libraries') as HTMLElement;
    groupTab.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
    expect(window.location.hash).toBe('#_g-group-Libraries');
    await until(() => display('g-group-Libraries') === '');
    expect(display('g-total')).toBe('none');
  });

  test('replaces the timeago timestamp with relative text', () => {
    expect(bodyText('#footer abbr.timeago')).toBe('10 hours ago');
  });

  test('reveals the report and fades the loading indicator away', async () => {
    const wrapper = document.getElementById('wrapper') as HTMLElement;
    expect(wrapper.classList.contains('hide')).toBe(false);

    const loading = document.getElementById('loading') as HTMLElement;
    expect(loading.style.transition).toBe('opacity 0.3s');
    expect(loading.style.opacity).toBe('0');
    await until(() => loading.style.display === 'none');
  });

  test('wires the theme and colorblind toggles', () => {
    expect(bodyText('.toolbar [data-toggle="dark"]')).toBe('🌙 Dark');

    const colorblind = document.querySelector('.toolbar [data-toggle="colorblind"]') as HTMLElement;
    colorblind.click();
    expect(document.documentElement.classList.contains('colorblind-mode')).toBe(true);
    colorblind.click();
    expect(document.documentElement.classList.contains('colorblind-mode')).toBe(false);
  });

  test('makes the column headers sortable', () => {
    const header = document.querySelector('#g-total thead th') as HTMLElement;
    expect(header.classList.contains('sorting')).toBe(true);
  });

  test('filters rows as the name filter is typed', () => {
    const input = document.querySelector('#g-total .col-filter--name') as HTMLInputElement;
    input.value = 'missed';
    input.dispatchEvent(new Event('input', {bubbles: true}));
    const rows = Array.from(document.querySelectorAll('#g-total tbody tr.t-file')) as HTMLElement[];
    const displayOf = (name: string): string => rows.find((row) => row.textContent!.includes(name))!.style.display;
    expect([displayOf('lib/covered.rb'), displayOf('lib/missed.rb')]).toEqual(['none', '']);
    input.value = '';
    input.dispatchEvent(new Event('input', {bubbles: true}));
  });

  test('answers the keyboard shortcuts', () => {
    document.body.dispatchEvent(new KeyboardEvent('keydown', {key: '/', bubbles: true, cancelable: true}));
    const visible = Array.from(document.querySelectorAll<HTMLElement>('.file_list_container')).find((c) => c.style.display !== 'none')!;
    expect(document.activeElement === visible.querySelector('.col-filter--name')).toBe(true);
    (document.activeElement as HTMLElement).blur();
  });

  test('marks the tab strip once it scrolls', () => {
    const strip = document.querySelector('.group_tabs') as HTMLElement;
    Object.defineProperty(strip, 'scrollLeft', {configurable: true, get: () => 120});
    strip.dispatchEvent(new Event('scroll'));
    expect(strip.classList.contains('is-scrolled')).toBe(true);
  });
});

describe('booting again', () => {
  test('shows the loading indicator while the data is being prepared', async () => {
    await prepareBoot('');
    startBoot();
    expect(display('loading')).toBe('');
    await until(() => bodyText('#footer').includes('simplecov'));
  });

  test('hides every file list behind a source dialog opened from the URL', async () => {
    await precomputeFileIds(['lib/covered.rb']);
    await boot('#' + fileId('lib/covered.rb'));
    expect((document.getElementById('source-dialog') as HTMLDialogElement).open).toBe(true);
    expect(display('g-total')).toBe('none');
    expect(display('g-group-Libraries')).toBe('none');
  });

  test('sizes the coverage bars once the report is revealed and again on resize', async () => {
    const offsetWidth = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'offsetWidth')!;
    Object.defineProperty(HTMLElement.prototype, 'offsetWidth', {configurable: true, get: () => 800});
    try {
      await boot();
      const table = document.querySelector('#g-total table.file_list') as HTMLElement;
      expect(table.style.getPropertyValue('--bar-sizer-width')).toBe('235px');

      table.style.removeProperty('--bar-sizer-width');
      window.dispatchEvent(new Event('resize'));
      await nextFrame();
      expect(table.style.getPropertyValue('--bar-sizer-width')).toBe('235px');
    } finally {
      Object.defineProperty(HTMLElement.prototype, 'offsetWidth', offsetWidth);
    }
  });
});

describe('scheduleTimeago', () => {
  function abbrs(): string[] {
    return Array.from(document.querySelectorAll('abbr.timeago')).map((el) => el.textContent!);
  }

  test('leaves elements without a parsable timestamp alone and schedules nothing', () => {
    document.body.innerHTML = '<abbr class="timeago">keep</abbr><abbr class="timeago" title="not a date">keep too</abbr>';
    const timer = spyOn(globalThis, 'setTimeout').mockImplementation((() => 0) as unknown as typeof setTimeout);
    scheduleTimeago();
    expect(abbrs()).toEqual(['keep', 'keep too']);
    expect(timer).not.toHaveBeenCalled();
  });

  test('rewrites every timestamp and reschedules for the soonest change', () => {
    const now = Date.now();
    document.body.innerHTML =
      `<abbr class="timeago" title="${new Date(now - 10 * 3600 * 1000).toISOString()}"></abbr>` +
      `<abbr class="timeago" title="${new Date(now - 30 * 1000).toISOString()}"></abbr>`;
    const timer = spyOn(globalThis, 'setTimeout').mockImplementation((() => 0) as unknown as typeof setTimeout);
    scheduleTimeago();
    expect(abbrs()).toEqual(['10 hours ago', '30 seconds ago']);
    expect(timer).toHaveBeenCalledTimes(1);
    const [callback, delay] = timer.mock.calls[0] as unknown as [() => void, number];
    expect(callback).toBe(scheduleTimeago);
    expect(delay).toBeGreaterThanOrEqual(1000);
    expect(delay).toBeLessThan(2000);
  });
});
