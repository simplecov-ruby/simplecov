// Equalizes the coverage-bar column width across all rows of each visible
// file list, via a binary search that fits the widest bar without overflow.

import { $, $$ } from './dom';

const MAX_BAR_WIDTH = 240;
const MIN_BAR_WIDTH = 160;

function setBarSizerWidth(sizers: Element[], px: number): void {
  const w = px + 'px';
  sizers.forEach(s => {
    const st = (s as HTMLElement).style;
    st.width = w;
    st.minWidth = w;
    st.maxWidth = w;
  });
}

export function equalizeBarWidths(): void {
  $$('.file_list_container').forEach(container => {
    if ((container as HTMLElement).style.display === 'none') return;
    if ((container as HTMLElement).offsetWidth === 0) return;

    const table = $('table.file_list', container) as HTMLTableElement | null;
    if (!table) return;
    const sizers = $$('.bar-sizer', table);
    if (sizers.length === 0) return;

    const wrapper = table.closest('.file_list--responsive') as HTMLElement | null;
    if (!wrapper) return;

    wrapper.style.visibility = 'hidden';

    let lo = MIN_BAR_WIDTH, hi = MAX_BAR_WIDTH;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      setBarSizerWidth(sizers, mid);
      void table.offsetWidth;
      if (table.scrollWidth <= wrapper.clientWidth) lo = mid;
      else hi = mid - 1;
    }
    setBarSizerWidth(sizers, lo);

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
