// Equalizes the coverage-bar column width across all rows of each visible
// file list, via a binary search that fits the widest bar without overflow.

import { $, $$ } from './dom';

const MAX_BAR_WIDTH = 240;
const MIN_BAR_WIDTH = 160;

// Every .bar-sizer in a table shares one width, so it lives in a CSS custom
// property on the table (see .bar-sizer in screen.css) rather than in inline
// styles. Each binary-search probe below is then a single style write instead
// of one write per sizer, which matters on reports with thousands of rows.
function setBarSizerWidth(table: HTMLElement, px: number): void {
  table.style.setProperty('--bar-sizer-width', px + 'px');
}

export function equalizeBarWidths(): void {
  $$('.file_list_container').forEach(container => {
    if ((container as HTMLElement).style.display === 'none') return;
    if ((container as HTMLElement).offsetWidth === 0) return;

    const table = $('table.file_list', container) as HTMLTableElement | null;
    if (!table) return;
    if (!$('.bar-sizer', table)) return;

    const wrapper = table.closest('.file_list--responsive') as HTMLElement | null;
    if (!wrapper) return;

    wrapper.style.visibility = 'hidden';

    let lo = MIN_BAR_WIDTH, hi = MAX_BAR_WIDTH;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      setBarSizerWidth(table, mid);
      void table.offsetWidth;
      if (table.scrollWidth <= wrapper.clientWidth) lo = mid;
      else hi = mid - 1;
    }
    setBarSizerWidth(table, lo);

    wrapper.style.visibility = '';
  });
}

let equalizeRafId = 0;

export function scheduleEqualizeBarWidths(): void {
  if (equalizeRafId) return;
  equalizeRafId = requestAnimationFrame(() => {
    equalizeRafId = 0;
    equalizeBarWidths();
  });
}
