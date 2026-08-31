import { beforeAll, describe, expect, test } from 'bun:test';
import { setupColumnFilters } from '../src/filter';

const OPS_MARKUP = `
  <option value="lt">&lt;</option>
  <option value="lte" selected>&le;</option>
  <option value="eq">=</option>
  <option value="gte">&ge;</option>
  <option value="gt">&gt;</option>`;

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
      <tbody>
        <tr class="t-file" data-covered-lines="3" data-relevant-lines="4"><td>lib/alpha.rb</td><td data-order="75.00">75.00</td></tr>
        <tr class="t-file" data-covered-lines="4" data-relevant-lines="4"><td>lib/beta.rb</td><td data-order="100.00">100.00</td></tr>
        <tr class="t-file"><td>lib/empty.rb</td><td></td></tr>
      </tbody>
    </table>
  </div>`;

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

function fire(el: Element, type: string): void {
  el.dispatchEvent(new Event(type, { bubbles: true, cancelable: true }));
}

function visibleNames(): string[] {
  return Array.from(document.querySelectorAll('tbody tr.t-file'))
    .filter((row) => (row as HTMLElement).style.display !== 'none')
    .map((row) => (row.children[0].textContent || '').trim());
}

beforeAll(() => {
  document.body.innerHTML = CONTAINER_MARKUP;
  setupColumnFilters();
});

describe('filename filtering', () => {
  test('narrows to matching rows, case-insensitively, and restores on clear', () => {
    nameInput().value = '  ALPHA ';
    fire(nameInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb']);

    nameInput().value = 'lib/';
    fire(nameInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb', 'lib/beta.rb', 'lib/empty.rb']);

    nameInput().value = '';
    fire(nameInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb', 'lib/beta.rb', 'lib/empty.rb']);
  });
});

describe('coverage threshold filtering', () => {
  const CASES: [string, string, string[]][] = [
    ['lt', '80', ['lib/alpha.rb']],
    ['lte', '75', ['lib/alpha.rb']],
    ['eq', '100', ['lib/beta.rb', 'lib/empty.rb']],
    ['gte', '100', ['lib/beta.rb', 'lib/empty.rb']],
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
});

describe('operator option maintenance', () => {
  test('disables impossible operators and hops off a disabled selection', () => {
    opSelect().value = 'gt';
    valueInput().value = '100';
    fire(valueInput(), 'input');
    const gtOption = opSelect().querySelector('option[value="gt"]') as HTMLOptionElement;
    expect(gtOption.disabled).toBe(true);
    expect(opSelect().value).toBe('lt');

    valueInput().value = '0';
    fire(valueInput(), 'input');
    const ltOption = opSelect().querySelector('option[value="lt"]') as HTMLOptionElement;
    expect(ltOption.disabled).toBe(true);
    expect(opSelect().value).toBe('lte');

    valueInput().value = '100';
    opSelect().value = 'lte';
    fire(valueInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb', 'lib/beta.rb', 'lib/empty.rb']);
  });

  test('bails when a value input has no operator wrapper', () => {
    const loose = document.createElement('input');
    loose.className = 'col-filter__value';
    loose.value = '';
    container().appendChild(loose);
    fire(loose, 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb', 'lib/beta.rb', 'lib/empty.rb']);
    loose.remove();
  });
});

describe('malformed filter inputs', () => {
  test('skips empty, non-numeric, unknown-type, and op-less inputs; unknown ops match everything', () => {
    container().insertAdjacentHTML(
      'beforeend',
      `<span class="extras">
        <input class="col-filter__value" data-type="branch" value="">
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

    fire(valueInput(), 'input');
    expect(visibleNames()).toEqual(['lib/alpha.rb', 'lib/beta.rb', 'lib/empty.rb']);

    container().querySelector('.extras')!.remove();
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
