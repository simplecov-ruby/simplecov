import { beforeAll, describe, expect, test } from 'bun:test';
import { coverageData, installPageSkeleton } from './fixture';
import '../src/app';

function bodyText(selector: string): string {
  const el = document.querySelector(selector);
  return el ? el.textContent || '' : '';
}

async function until(check: () => boolean): Promise<void> {
  for (let i = 0; i < 200; i++) {
    if (check()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error('condition never became true');
}

describe('application boot', () => {
  beforeAll(async () => {
    installPageSkeleton();
    window.location.hash = '';

    const data = coverageData();
    data.groups = {Libraries: {files: ['lib/covered.rb'], lines: {covered: 3, missed: 0, total: 3, percent: 100, strength: 1}}};
    data.meta.timestamp = new Date(Date.now() - 10 * 3600 * 1000).toISOString();
    window.SIMPLECOV_DATA = data;

    document.dispatchEvent(new Event('DOMContentLoaded'));
    await until(() => bodyText('#footer').includes('simplecov'));
  });

  test('renders the file lists and footer from the embedded data', () => {
    expect(document.title).toBe('Code coverage for Sample Project');
    expect(bodyText('#g-total')).toContain('lib/covered.rb');
    expect(bodyText('#g-total')).toContain('lib/missed.rb');
    expect(bodyText('#footer')).toContain('using RSpec');
  });

  test('builds one tab per group and shows the All Files tab first', () => {
    const tabs = Array.from(document.querySelectorAll('.group_tabs a'));
    expect(tabs.map((tab) => tab.getAttribute('href'))).toEqual(['#g-total', '#g-group-Libraries']);
    expect((document.getElementById('g-total') as HTMLElement).style.display).toBe('');
    expect((document.getElementById('g-group-Libraries') as HTMLElement).style.display).toBe('none');
  });

  test('switches groups when a tab is clicked', async () => {
    const groupTab = document.querySelector('.group_tabs a.g-group-Libraries') as HTMLElement;
    groupTab.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
    expect(window.location.hash).toBe('#_g-group-Libraries');
    await until(() => (document.getElementById('g-group-Libraries') as HTMLElement).style.display === '');
    expect((document.getElementById('g-total') as HTMLElement).style.display).toBe('none');
  });

  test('replaces the timeago timestamp with relative text', () => {
    expect(bodyText('#footer abbr.timeago')).toBe('10 hours ago');
  });

  test('reveals the report and fades the loading indicator away', async () => {
    const wrapper = document.getElementById('wrapper') as HTMLElement;
    expect(wrapper.classList.contains('hide')).toBe(false);

    const loading = document.getElementById('loading') as HTMLElement;
    expect(loading.style.opacity).toBe('0');
    await until(() => loading.style.display === 'none');
  });
});
