// Static layout-contract tests for the duplicated theme controls. happy-dom
// does not perform browser layout, so these assert the CSS equations that make
// the index and source-dialog rectangles identical in a real browser.
import { beforeAll, describe, expect, test } from 'bun:test';

let css = '';
let template = '';

beforeAll(async () => {
  [css, template] = await Promise.all([
    Bun.file('assets/stylesheets/screen.css').text(),
    Bun.file('src/index.html').text()
  ]);
  css = css.replace(/\/\*[\s\S]*?\*\//g, '');
});

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// `declaration` stops at the first closing brace, so the nested @media print
// rules need the block sliced out by brace matching first.
function printBlock(): string {
  const start = css.indexOf('@media print');
  let depth = 0;
  for (let i = css.indexOf('{', start); i < css.length; i++) {
    if (css[i] === '{') depth += 1;
    if (css[i] === '}' && (depth -= 1) === 0) return css.slice(start, i);
  }
  throw new Error('Missing @media print block');
}

function declaration(selector: string, property: string): string {
  const rule = css.match(new RegExp(`${escapeRegex(selector)}\\s*\\{([^}]*)\\}`));
  if (!rule) throw new Error(`Missing CSS rule: ${selector}`);

  const value = rule[1].match(new RegExp(`(?:^|;)\\s*${escapeRegex(property)}\\s*:\\s*([^;]+)`));
  if (!value) throw new Error(`Missing ${property} in ${selector}`);

  return value[1].trim();
}

describe('theme-control layout contract', () => {
  test('renders identical controls in the index and source views', () => {
    const document = new DOMParser().parseFromString(template, 'text/html');
    const index = document.querySelector('.toolbar')!;
    const source = document.querySelector('.source-dialog__toggles')!;
    const controls = (container: Element): string[] =>
      Array.from(container.querySelectorAll('.toolbar-toggle'), (button) => button.outerHTML);

    expect(controls(index)).toEqual(controls(source));
    expect(source.nextElementSibling!.classList.contains('source-dialog__close')).toBe(true);
  });

  test('uses the same top coordinate and reserves the exact close-button slot', () => {
    const pageInset = declaration('body', 'padding');
    const sourceInset = declaration('.source-dialog__header', 'padding');
    const closeSize = declaration(':root', '--source-close-size');
    const closeGap = declaration(':root', '--source-close-gap');
    const closeSlot = declaration(':root', '--source-close-slot');

    expect(declaration(':root', '--sp-6')).toBe('24px');
    expect(sourceInset).toBe(pageInset);
    expect(closeSlot).toBe('calc(var(--source-close-size) + var(--source-close-gap))');
    expect(declaration('.toolbar', 'margin-right')).toBe('var(--source-close-slot)');
    expect(declaration('.source-dialog__close', 'width')).toBe('var(--source-close-size)');
    expect(declaration('.source-dialog__close', 'height')).toBe('var(--source-close-size)');
    expect(declaration('.source-dialog__close', 'margin-left')).toBe('var(--source-close-gap)');
    expect(declaration('.toolbar', 'gap')).toBe(declaration('.source-dialog__toggles', 'gap'));
    expect(closeSize).toBe('34px');
    expect(closeGap).toBe('var(--sp-4)');
  });

  test('uses the same grey page background behind both control groups', () => {
    expect(declaration(':root', '--bg')).toBe('#f0f1f3');
    expect(declaration('.source-dialog__header', 'background')).toBe(declaration('body', 'background'));
  });

  test('aligns each right-justified legend row with its coverage summary', () => {
    const document = new DOMParser().parseFromString(template, 'text/html');
    const legend = document.querySelector('.source-legend')!;
    const close = document.querySelector('.source-dialog__close')!;

    expect(legend.parentElement).toBe(close.parentElement);
    expect(declaration('.source-dialog__header', 'display')).toBe('grid');
    expect(declaration('.source-dialog__header', 'grid-template-columns')).toBe('minmax(0, 1fr) auto auto');
    expect(declaration('.source-dialog__title', 'display')).toBe('contents');
    expect(declaration('.source-dialog__title .summary-stats', 'display')).toBe('contents');
    expect(declaration('.source-legend', 'display')).toBe('contents');
    expect(declaration('.source-legend__row', 'grid-column')).toBe('2 / 4');
    expect(declaration('.source-legend__row', 'align-self')).toBe('center');
    expect(declaration('.source-legend__row', 'justify-content')).toBe('flex-end');

    for (const [type, row] of [['line', '2'], ['branch', '3'], ['method', '4']]) {
      expect(declaration(`.source-dialog__title .t-${type}-summary`, 'grid-row')).toBe(row);
      expect(declaration(`.source-legend__row--${type}`, 'grid-row')).toBe(row);
    }
  });

  // Opening the dialog freezes the page behind it with overflow: hidden, which
  // reclaims the scrollbar's width on every platform that gives it layout
  // space. Without a reserved gutter the viewport widens at that moment and
  // the toggles slide sideways, which is the shift this alignment prevents.
  test('holds the viewport width steady while the dialog locks page scrolling', () => {
    expect(declaration('html', 'scrollbar-gutter')).toBe('stable');
  });

  // The grid seats each legend row in the columns the toggles and close button
  // occupy. Neither prints, so on paper the header returns to document flow
  // and the legend rows print full width under the summaries.
  test('prints the header in document flow instead of the screen grid', () => {
    const print = printBlock();
    expect(print).toMatch(/\.source-dialog__header\s*\{[^}]*display:\s*block/);
    expect(print).toMatch(/\.source-legend__row\s*\{[^}]*justify-content:\s*flex-start/);
  });
});
