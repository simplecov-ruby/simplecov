
import { $ } from './dom';

export function setupTabScrollFade(): void {
  const strip = $('.group_tabs') as HTMLElement | null;
  if (!strip) return;

  const sync = (): void => {
    strip.classList.toggle('is-scrolled', strip.scrollLeft > 0);
  };

  strip.addEventListener('scroll', sync);
  window.addEventListener('resize', sync);
  sync();
}
