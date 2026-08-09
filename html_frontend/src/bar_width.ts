// Equalizes the coverage-bar column width across all rows of each visible
// file list, via a binary search that fits the widest bar without overflow.

import { $, $$ } from './dom';

const MAX_BAR_WIDTH = 240;
const MIN_BAR_WIDTH = 160;

// Every .bar-sizer in a table shares one width, so it lives in a CSS custom
// property on the table (see .bar-sizer in screen.css) rather than in inline
// styles. Each probe below is then a single style write instead of one write
// per sizer, which matters on reports with thousands of rows.
function setBarSizerWidth(table: HTMLElement, px: number): void {
  table.style.setProperty('--bar-sizer-width', px + 'px');
}

// The table width is not a clean linear function of the bar width — there are
// three bar columns sharing the width variable, and column min-widths make
// scrollWidth step irregularly — so the fit can only be found by probing, not
// solving. Stop the search once the bracket is within STEP px of the answer
// instead of resolving it to the pixel: each probe forces a reflow, and a
// reflow of a large file list is expensive (it was the single biggest finalize
// cost on a 100k-file report). STEP px narrower than optimal is imperceptible
// on a 160–240px bar, and the search still returns a width that fits, so the
// table never overflows.
const BAR_WIDTH_STEP = 8;

// Widest bar width in [MIN, MAX], to within BAR_WIDTH_STEP, that keeps the
// table from overflowing its wrapper.
function fitBarWidth(table: HTMLElement, client: number): number {
  let lo = MIN_BAR_WIDTH, hi = MAX_BAR_WIDTH;
  while (hi - lo > BAR_WIDTH_STEP) {
    const mid = Math.ceil((lo + hi) / 2);
    setBarSizerWidth(table, mid);
    void table.offsetWidth;
    if (table.scrollWidth <= client) lo = mid;
    else hi = mid - 1;
  }
  return lo;
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
    setBarSizerWidth(table, fitBarWidth(table, wrapper.clientWidth));
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
