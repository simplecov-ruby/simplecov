import { beforeAll, describe, expect, spyOn, test } from 'bun:test';
import { setupColumnFilters } from '../src/filter';
import { getVisibleFileRows } from '../src/file_rows';

const OPS_MARKUP = `
  <option value="lt">&lt;</option>
  <option value="lte" selected>&le;</option>
  <option value="eq">=</option>
  <option value="gte">&ge;</option>
  <option value="gt">&gt;</option>`;

const ROWS_MARKUP = `
        <tr class="t-file" data-covered-lines="3" data-relevant-lines="4"><td>lib/alpha.rb</td><td data-order="75.00">75.00</td></tr>
        <tr class="t-file" data-covered-lines="4" data-relevant-lines="4"><td>lib/beta.rb</td><td data-order="100.00">100.00</td></tr>
        <tr class="t-file"><td>lib/empty.rb</td><td></td></tr>`;

const CONTAINER_MARKUP = `
  <div class="file_list_container" data-total-files="3">
    <table class="file_list">
      <thead>
        <tr>
          <th><input type="search" class="col-filter col-filter--name"></th>
          <th>
            <div class="col-filter__coverage">
              <select class="col-filter__op" data-type="line">${OPS_MARKUP}</select>
              <input type="number" class="col-filter__value" min="0" max="100" data-type="line" value="100">
            </div>
          </th>
        </tr>
        <tr class="totals-row">
          <td class="strong t-file-count"></td>
          <td class="t-totals__line-pct"></td>
        </tr>
      </thead>
      <tbody>${ROWS_MARKUP}
      </tbody>
    </table>
  </div>`;

function edgeContainer(options: string, value: string): string {
  return `
  <div class="file_list_container edge" data-total-files="1">
    <table class="file_list">
      <thead><tr><th>
        <div class="col-filter__coverage">
          <select class="col-filter__op" data-type="line">${options}</select>
          <input type="number" class="col-filter__value" data-type="line" value="${value}">
        </div>
      </th></tr></thead>
      <tbody>
        <tr class="t-file" data-covered-lines="3" data-relevant-lines="4"><td>lib/alpha.rb</td></tr>
      </tbody>
    </table>
  </div>`;
}

function container(): HTMLElement {
  return document.querySelector('.file_list_container') as HTMLElement;
}

function nameInput(): HTMLInputElement {
  return document.querySelector('.col-filter--name') as HTMLInputElement;
}

function opSelect(): HTMLSelectElement {
  return document.querySelector('.col-filter__op') as HTMLSelectElement;
}

function valueInput(): HTMLInputElement {
  return document.querySelector('.col-filter__value') as HTMLInputElement;
}

function option(value: string): HTMLOptionElement {
  return opSelect().querySelector(`option[value="${value}"]`) as HTMLOptionElement;
}

function fire(el: Element, type: string): void {
  el.dispatchEvent(new Event(type, { bubbles: true, cancelable: true }));
}

function visibleNames(): string[] {
  return Array.from(document.querySelectorAll('tbody tr.t-file'))
    .filter((row) => (row as HTMLElement).style.display !== 'none')
    .map((row) => (row.children[0].textContent || '').trim());
}

function fileCount(): string {
  return container().querySelector('.t-file-count')!.textContent!;
}

function reset(): void {
  nameInput().value = '';
  opSelect().value = 'lte';
  valueInput().value = '100';
  fire(valueInput(), 'input');
}

beforeAll(() => {
  document.body.innerHTML = CONTAINER_MARKUP;
  setupColumnFilters();
});

describe('initial operator state', () => {
  test('disables the operators the initial values make impossible', () => {
    expect(option('gt').disabled).toBe(true);
    expect(option('lt').disabled).toBe(false);
    expect(opSelect().value).toBe('lte');
  });
});

describe('sort-click isolation', () => {
  test('clicks on filter controls do not bubble to the sortable header', () => {
    let reached = 0;
    const table = container().querySelector('table')!;
    const listener = (): void => {
      reached += 1;
    };
    table.addEventListener('click', listener);

    fire(nameInput(), 'click');
    fire(opSelect(), 'click');
    fire(valueInput(), 'click');
    fire(container().querySelector('.col-filter__coverage')!, 'click');
    expect(reached).toBe(0);

    table.removeEventListener('click', listener);
  });
});

describe('filename filtering', () => {
  test('narrows to matching rows, case-insensitively, and restores on clear', () => {
    nameInput().value = '  ALPHA ';
    fire(nameInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb']);
    expect(fileCount()).toBe('1/3 file');

    nameInput().value = 'lib/';
    fire(nameInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb', 'lib/beta.rb', 'lib/empty.rb']);
    expect(fileCount()).toBe('3 files');

    nameInput().value = '';
    fire(nameInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb', 'lib/beta.rb', 'lib/empty.rb']);
  });

  test('remembers each row\'s name from its first filtering', () => {
    const alphaCell = container().querySelector('tbody tr.t-file td')!;
    alphaCell.textContent = 'lib/renamed.rb';
    nameInput().value = 'alpha';
    fire(nameInput(), 'input');
    expect(visibleNames()).toEqual(['lib/renamed.rb']);

    alphaCell.textContent = 'lib/alpha.rb';
    reset();
  });

  test('refreshes the keyboard navigation rows', () => {
    expect(getVisibleFileRows()).toHaveLength(3);
    nameInput().value = 'beta';
    fire(nameInput(), 'input');
    expect(getVisibleFileRows()).toHaveLength(1);
    reset();
  });

  test('schedules the bar widths to be equalized', async () => {
    await new Promise((resolve) => requestAnimationFrame(() => resolve(null)));
    const raf = spyOn(window, 'requestAnimationFrame');
    nameInput().value = 'beta';
    fire(nameInput(), 'input');
    expect(raf).toHaveBeenCalledTimes(1);
    raf.mockRestore();
    reset();
  });

  test('filters a container that has no name filter by its columns alone', () => {
    document.body.innerHTML = edgeContainer(OPS_MARKUP, '');
    valueInput().value = '80';
    fire(valueInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb']);

    document.body.innerHTML = CONTAINER_MARKUP;
    reset();
  });
});

describe('coverage threshold filtering', () => {
  const CASES: [string, string, string[]][] = [
    ['lt', '80', ['lib/alpha.rb']],
    ['lt', '75', []],
    ['lte', '75', ['lib/alpha.rb']],
    ['eq', '100', ['lib/beta.rb', 'lib/empty.rb']],
    ['gte', '100', ['lib/beta.rb', 'lib/empty.rb']],
    ['gt', '75', ['lib/beta.rb', 'lib/empty.rb']],
    ['gt', '99', ['lib/beta.rb', 'lib/empty.rb']]
  ];

  test('applies each comparison operator against the row percentage', () => {
    for (const [op, threshold, expected] of CASES) {
      opSelect().value = op;
      valueInput().value = threshold;
      fire(valueInput(), 'input');
      expect(visibleNames()).toEqual(expected);
    }

    opSelect().value = 'lte';
    valueInput().value = '100';
    fire(valueInput(), 'change');
    fire(opSelect(), 'change');
    expect(visibleNames()).toEqual(['lib/alpha.rb', 'lib/beta.rb', 'lib/empty.rb']);
  });

  test('requires every column filter to pass', () => {
    container().insertAdjacentHTML(
      'beforeend',
      `<div class="col-filter__coverage extras">
        <select class="col-filter__op" data-type="method"><option value="gte" selected>&ge;</option></select>
        <input class="col-filter__value" data-type="method" value="0">
      </div>`
    );
    opSelect().value = 'lt';
    valueInput().value = '80';
    fire(valueInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb']);

    container().querySelector('.extras')!.remove();
    reset();
  });

  test('rows with a zero denominator count as fully covered', () => {
    opSelect().value = 'eq';
    valueInput().value = '100';
    fire(valueInput(), 'input');
    expect(visibleNames()).toContain('lib/empty.rb');
    reset();
  });
});

describe('operator option maintenance', () => {
  test('disables impossible operators and hops off a disabled selection', () => {
    opSelect().value = 'gt';
    valueInput().value = '100';
    fire(valueInput(), 'input');
    expect(option('gt').disabled).toBe(true);
    expect(opSelect().value).toBe('lt');

    valueInput().value = '0';
    fire(valueInput(), 'input');
    expect(option('lt').disabled).toBe(true);
    expect(opSelect().value).toBe('lte');

    valueInput().value = '100';
    opSelect().value = 'lte';
    fire(valueInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb', 'lib/beta.rb', 'lib/empty.rb']);
  });

  test('maintains the options on change events too', () => {
    valueInput().value = '0';
    fire(valueInput(), 'change');
    expect(option('lt').disabled).toBe(true);
    expect(option('gt').disabled).toBe(false);
    reset();
  });

  test('leaves the options alone when the operator itself changes', () => {
    valueInput().value = '100';
    fire(valueInput(), 'input');
    expect(option('gt').disabled).toBe(true);

    opSelect().value = 'eq';
    fire(opSelect(), 'change');
    expect(option('gt').disabled).toBe(true);
    reset();
  });

  test('bails when a value input has no operator wrapper, still filtering', () => {
    const loose = document.createElement('input');
    loose.className = 'col-filter__value';
    loose.value = '';
    container().appendChild(loose);
    nameInput().value = 'alpha';
    fire(loose, 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb']);
    loose.remove();
    reset();
  });

  test('copes with a select that lacks the operator it would disable', () => {
    document.body.innerHTML = edgeContainer('<option value="lt" selected>&lt;</option>', '');
    valueInput().value = '0';
    fire(valueInput(), 'input');
    expect(option('lt').disabled).toBe(true);
    expect(opSelect().value).toBe('lt');
    expect(visibleNames()).toEqual([]);

    document.body.innerHTML = edgeContainer('<option value="gt" selected>&gt;</option>', '');
    valueInput().value = '100';
    fire(valueInput(), 'input');
    expect(option('gt').disabled).toBe(true);
    expect(opSelect().value).toBe('gt');
    expect(visibleNames()).toEqual([]);

    document.body.innerHTML = CONTAINER_MARKUP;
    reset();
  });
});

describe('malformed filter inputs', () => {
  test('skips empty, non-numeric, unknown-type, and op-less inputs; unknown ops match everything', () => {
    container().insertAdjacentHTML(
      'beforeend',
      `<span class="extras">
        <div class="col-filter__coverage">
          <select class="col-filter__op" data-type="branch"><option value="lte" selected>&le;</option></select>
          <input class="col-filter__value" data-type="branch" value="">
        </div>
        <input class="col-filter__value" data-type="branch" value="not-a-number">
        <input class="col-filter__value" value="50">
        <div class="col-filter__coverage">
          <select class="col-filter__op" data-type="weird"><option value="lte" selected>&le;</option></select>
          <input class="col-filter__value" data-type="weird" value="50">
        </div>
        <div class="col-filter__coverage">
          <select class="col-filter__op" data-type="method"><option value="bogus" selected>?</option></select>
          <input class="col-filter__value" data-type="method" value="50">
        </div>
      </span>`
    );

    opSelect().value = 'lt';
    valueInput().value = '80';
    fire(valueInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb']);

    container().querySelector('.extras')!.remove();
    reset();
  });

  test('ignores containers without a file table', () => {
    document.body.insertAdjacentHTML(
      'beforeend',
      '<div class="file_list_container tableless"><input type="search" class="col-filter col-filter--name"></div>'
    );
    const tableless = document.querySelector('.tableless input') as HTMLInputElement;
    tableless.value = 'anything';
    fire(tableless, 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb', 'lib/beta.rb', 'lib/empty.rb']);
    document.querySelector('.tableless')!.remove();
  });
});

describe('row windowing', () => {
  test('re-windows the table after filtering', () => {
    const rows = Array.from({ length: 1001 }, (_, i) =>
      `<tr class="t-file" data-covered-lines="1" data-relevant-lines="1"><td>lib/file_${i}.rb</td><td>100.00</td></tr>`
    ).join('');
    document.body.innerHTML = CONTAINER_MARKUP.replace(ROWS_MARKUP, rows).replace('data-total-files="3"', 'data-total-files="1001"');
    nameInput().value = 'lib/';
    fire(nameInput(), 'input');
    expect(container().querySelector('tr.t-show-all')).not.toBeNull();
    expect(container().querySelectorAll('tr.t-file.t-window-hidden')).toHaveLength(1);

    document.body.innerHTML = CONTAINER_MARKUP;
    reset();
  });
});
