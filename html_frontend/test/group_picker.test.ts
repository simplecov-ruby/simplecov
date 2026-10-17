import { beforeEach, describe, expect, test } from 'bun:test';
import { setupGroupPicker, syncGroupPicker } from '../src/group_picker';

function buildTabs(names: string[], active = 0): void {
  const tabs = names.map((name, i) => {
    const id = i === 0 ? 'g-total' : `g-group-${name}`;
    return `<li role="tab"${i === active ? ' class="active"' : ''}><a href="#${id}" class="${id}">${name} (<span class="green">90.00%</span>)</a></li>`;
  });
  document.body.innerHTML = `<div class="tab-bar"><ul class="group_tabs">${tabs.join('')}</ul></div>`;
}

function picker(): HTMLSelectElement | null {
  return document.querySelector('select.group_picker');
}

beforeEach(() => {
  document.body.innerHTML = '';
  window.location.hash = '';
});

describe('setupGroupPicker', () => {
  test('adds no picker when there is only one group', () => {
    buildTabs(['All Files']);
    setupGroupPicker();
    expect(picker()).toBeNull();
  });

  test('mirrors every tab as an option, placed just before the tab strip', () => {
    buildTabs(['All Files', 'Models', 'Controllers'], 1);
    setupGroupPicker();
    const select = picker()!;

    expect(select.nextElementSibling!.classList.contains('group_tabs')).toBe(true);
    expect(select.getAttribute('aria-label')).toBe('Coverage group');
    expect(Array.from(select.options, (o) => [o.value, o.textContent])).toEqual([
      ['g-total', 'All Files (90.00%)'],
      ['g-group-Models', 'Models (90.00%)'],
      ['g-group-Controllers', 'Controllers (90.00%)']
    ]);
    expect(select.value).toBe('g-group-Models');
  });

  test('switches groups the way a tab click does', () => {
    buildTabs(['All Files', 'Models']);
    setupGroupPicker();
    const select = picker()!;

    select.value = 'g-group-Models';
    select.dispatchEvent(new Event('change'));
    expect(window.location.hash).toBe('#_g-group-Models');
  });
});

describe('syncGroupPicker', () => {
  test('selects the shown group', () => {
    buildTabs(['All Files', 'Models']);
    setupGroupPicker();
    syncGroupPicker('g-group-Models');
    expect(picker()!.value).toBe('g-group-Models');
  });

  test('does nothing without a picker', () => {
    buildTabs(['All Files']);
    expect(() => syncGroupPicker('g-total')).not.toThrow();
  });
});
