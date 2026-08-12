// Marks the group tab strip while it is scrolled away from its start, so the
// stylesheet can fade the leading edge to show that tabs continue off to the
// left. The trailing edge fades unconditionally, since trailing padding keeps
// the last tab clear of it, but the leading edge has no such padding to hide
// behind: it would dim the first tab of a strip that never scrolled.

import { $ } from './dom';

export function setupTabScrollFade(): void {
  const strip = $('.group_tabs') as HTMLElement | null;
  if (!strip) return;

  const sync = (): void => {
    strip.classList.toggle('is-scrolled', strip.scrollLeft > 0);
  };

  strip.addEventListener('scroll', sync);
  // A window that widens can fit every tab again and reset the scroll offset
  // without the strip itself reporting a scroll.
  window.addEventListener('resize', sync);
  sync();
}
