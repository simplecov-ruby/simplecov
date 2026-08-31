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
    expect(declaration('.source-dialog__toggles', 'justify-self')).toBe('end');
    expect(closeSize).toBe('34px');
    expect(closeGap).toBe('var(--sp-4)');
  });

  test('uses the same grey page background behind both control groups', () => {
    expect(declaration(':root', '--bg')).toBe('#f0f1f3');
    expect(declaration('.source-dialog__header', 'background')).toBe(declaration('body', 'background'));
  });

  test('aligns each legend row with its summary via subgrid rows and columns', () => {
    const document = new DOMParser().parseFromString(template, 'text/html');
    const legend = document.querySelector('.source-legend')!;
    const close = document.querySelector('.source-dialog__close')!;

    expect(legend.parentElement).toBe(close.parentElement);
    expect(declaration('.source-dialog__header', 'display')).toBe('grid');
    expect(declaration('.source-dialog__header', 'grid-template-columns')).toBe('minmax(0, 1fr) auto auto');
    expect(declaration('.source-dialog__title', 'display')).toBe('contents');
    expect(declaration('.source-dialog__title .summary-stats', 'display')).toBe('contents');
    expect(declaration('.source-legend', 'display')).toBe('grid');
    expect(declaration('.source-legend', 'grid-column')).toBe('2 / 3');
    expect(declaration('.source-legend', 'grid-row')).toBe('2 / 5');
    expect(declaration('.source-legend', 'grid-template-rows')).toBe('subgrid');
    expect(declaration('.source-legend', 'grid-template-columns')).toBe('repeat(4, auto)');
    expect(declaration('.source-legend', 'justify-content')).toBe('end');
    expect(declaration('.source-legend', 'justify-items')).toBe('start');
    expect(declaration('.source-legend__row', 'display')).toBe('contents');

    for (const [type, row, legendRow] of [['line', '2', '1'], ['branch', '3', '2'], ['method', '4', '3']]) {
      expect(declaration(`.source-dialog__title .t-${type}-summary`, 'grid-row')).toBe(row);
      expect(declaration(`.source-legend__row--${type} .source-legend__item`, 'grid-row')).toBe(legendRow);
    }
    for (const type of ['branch', 'method']) {
      expect(declaration(`.source-legend__row--${type} .source-legend__item`, 'grid-column')).toBe('4');
    }
    expect(declaration('.source-legend__row--line .source-legend__item:nth-last-child(1)', 'grid-column')).toBe('4');
    expect(declaration('.source-legend__row--line .source-legend__item:nth-last-child(2)', 'grid-column')).toBe('3');
    expect(declaration('.source-legend__row--line .source-legend__item:nth-last-child(3)', 'grid-column')).toBe('2');
    expect(declaration('.source-legend__row--line .source-legend__item:nth-last-child(4)', 'grid-column')).toBe('1');
  });

  test('holds the viewport width steady while the dialog locks page scrolling', () => {
    expect(declaration('html', 'scrollbar-gutter')).toBe('stable');
  });

  test('prints the header in document flow instead of the screen grid', () => {
    const print = printBlock();
    expect(print).toMatch(/\.source-dialog__header\s*\{[^}]*display:\s*block/);
    expect(print).toMatch(/\.source-legend\s*\{[^}]*justify-content:\s*flex-start/);
  });
});
