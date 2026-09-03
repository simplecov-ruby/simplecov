
import { $, $$, on } from './dom';
import { invalidateFileRowCache } from './file_rows';
import { scheduleEqualizeBarWidths } from './bar_width';
import { applyRowWindow } from './row_window';
import { dataAttrMap, updateTotalsRow, DataAttrPair } from './totals';

interface ActiveFilter {
  attrs: DataAttrPair;
  op: string;
  threshold: number;
}

const comparators: Record<string, (value: number, threshold: number) => boolean> = {
  gt:  (v, t) => v > t,
  gte: (v, t) => v >= t,
  eq:  (v, t) => v === t,
  lte: (v, t) => v <= t,
  lt:  (v, t) => v < t,
};

function compare(op: string, value: number, threshold: number): boolean {
  const comparator = comparators[op];
  return comparator ? comparator(value, threshold) : true;
}

function parseFilters(container: Element): ActiveFilter[] {
  const filters: ActiveFilter[] = [];
  for (const input of $$('.col-filter__value', container)) {
    const inp = input as HTMLInputElement;
    const threshold = Number.parseFloat(inp.value);
    if (Number.isNaN(threshold)) continue;

    const type = inp.dataset.type;
    const attrs = type && dataAttrMap[type];
    const opSelect = $(`.col-filter__op[data-type="${type}"]`, container) as HTMLSelectElement | null;
    if (attrs && opSelect) filters.push({ attrs, op: opSelect.value, threshold });
  }
  return filters;
}

const rowNameCache = new WeakMap<Element, string>();

function rowName(row: Element): string {
  let name = rowNameCache.get(row);
  if (name === undefined) {
    name = row.children[0].textContent!.toLowerCase();
    rowNameCache.set(row, name);
  }
  return name;
}

function filterTable(container: Element): void {
  const table = $('table.file_list', container) as HTMLTableElement | null;
  if (!table) return;

  const nameInput = $('.col-filter--name', container) as HTMLInputElement | null;
  const nameQuery = nameInput ? nameInput.value.trim().toLowerCase() : '';
  const filters = parseFilters(container);

  $$('tbody tr.t-file', table).forEach(row => {
    const htmlRow = row as HTMLElement;
    const visible = (!nameQuery || rowName(row).includes(nameQuery)) && filters.every((f) => {
      const covered = Number(htmlRow.dataset[f.attrs.covered]) || 0;
      const total = Number(htmlRow.dataset[f.attrs.total]) || 0;
      const pct = total > 0 ? (covered * 100.0) / total : 100;
      return compare(f.op, pct, f.threshold);
    });
    htmlRow.style.display = visible ? '' : 'none';
  });

  applyRowWindow(table);
  invalidateFileRowCache();
  updateTotalsRow(container);
  scheduleEqualizeBarWidths();
}

function updateFilterOptions(input: HTMLInputElement): void {
  const val = Number.parseFloat(input.value);
  const wrapper = input.closest('.col-filter__coverage');
  const select = wrapper ? wrapper.querySelector('.col-filter__op') as HTMLSelectElement | null : null;
  if (!select) return;
  const gtOpt = select.querySelector('option[value="gt"]') as HTMLOptionElement | null;
  const ltOpt = select.querySelector('option[value="lt"]') as HTMLOptionElement | null;
  if (gtOpt) gtOpt.disabled = val >= 100;
  if (ltOpt) ltOpt.disabled = val <= 0;
  if (select.selectedOptions[0] && select.selectedOptions[0].disabled) {
    const first = select.querySelector('option:not(:disabled)') as HTMLOptionElement | null;
    if (first) select.value = first.value;
  }
}

function refilter(this: Element): void {
  if (this.classList.contains('col-filter__value')) updateFilterOptions(this as HTMLInputElement);
  filterTable(this.closest('.file_list_container')!);
}

export function setupColumnFilters(): void {
  $$('.col-filter__value').forEach(el => updateFilterOptions(el as HTMLInputElement));

  $$('.col-filter--name, .col-filter__op, .col-filter__value, .col-filter__coverage').forEach(el => {
    el.addEventListener('click', e => e.stopPropagation());
  });

  on(document, 'input', '.col-filter--name, .col-filter__op, .col-filter__value', refilter);
  on(document, 'change', '.col-filter__op, .col-filter__value', refilter);
}
