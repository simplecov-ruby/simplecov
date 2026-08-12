// The leading-edge fade is class-driven because CSS alone cannot tell a strip
// that scrolled from one that never had to, so these cover the class going on
// and off again, and the resize path that a scroll event never reports.
import { beforeEach, describe, expect, test } from 'bun:test';
import { setupTabScrollFade } from '../src/tab_scroll';

function buildStrip(): HTMLElement {
  document.body.innerHTML = '<ul class="group_tabs"><li><a href="#g-total">All Files</a></li></ul>';
  const strip = document.querySelector('.group_tabs') as HTMLElement;
  // happy-dom performs no layout, so the scroll offset is ours to drive.
  let scrollLeft = 0;
  Object.defineProperty(strip, 'scrollLeft', {
    configurable: true,
    get: () => scrollLeft,
    set: (value: number) => { scrollLeft = value; }
  });
  return strip;
}

beforeEach(() => { document.body.innerHTML = ''; });

describe('setupTabScrollFade', () => {
  test('leaves a strip that has not scrolled unmarked', () => {
    const strip = buildStrip();
    setupTabScrollFade();
    expect(strip.classList.contains('is-scrolled')).toBe(false);
  });

  test('marks the strip once it scrolls and unmarks it on the way back', () => {
    const strip = buildStrip();
    setupTabScrollFade();

    strip.scrollLeft = 120;
    strip.dispatchEvent(new Event('scroll'));
    expect(strip.classList.contains('is-scrolled')).toBe(true);

    strip.scrollLeft = 0;
    strip.dispatchEvent(new Event('scroll'));
    expect(strip.classList.contains('is-scrolled')).toBe(false);
  });

  test('re-checks when the window resizes, which reports no scroll of its own', () => {
    const strip = buildStrip();
    setupTabScrollFade();

    strip.scrollLeft = 64;
    window.dispatchEvent(new Event('resize'));
    expect(strip.classList.contains('is-scrolled')).toBe(true);
  });

  test('does nothing on a page without a tab strip', () => {
    expect(() => setupTabScrollFade()).not.toThrow();
  });
});
