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

function mediaBlock(query: string): string {
  const start = css.indexOf(`${query} {`);
  if (start === -1) throw new Error(`Missing ${query} block`);
  let depth = 0;
  for (let i = css.indexOf('{', start); i < css.length; i++) {
    if (css[i] === '{') depth += 1;
    if (css[i] === '}' && (depth -= 1) === 0) return css.slice(css.indexOf('{', start) + 1, i);
  }
  throw new Error(`Unterminated ${query} block`);
}

function printBlock(): string {
  return mediaBlock('@media print');
}

const NARROW = '@media screen and (max-width: 640px)';
const SMALL = '@media screen and (max-width: 640px), screen and (max-height: 600px)';
const FIT_SOURCE = '@media screen and (max-width: 960px)';

function declaration(selector: string, property: string, source: string = css): string {
  const rule = source.match(new RegExp(`(?:^|[}\\s])${escapeRegex(selector)}\\s*\\{([^}]*)\\}`));
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

  test('labels each toggle with a word narrow screens can hide', () => {
    const document = new DOMParser().parseFromString(template, 'text/html');
    const labels = Array.from(document.querySelectorAll('[data-toggle="colorblind"] .toolbar-toggle__label'), (label) => label.textContent);
    expect(labels).toEqual(['Colorblind', 'Colorblind']);
  });

  test('prints the header in document flow instead of the screen grid', () => {
    const print = printBlock();
    expect(print).toMatch(/\.source-dialog__header\s*\{[^}]*display:\s*block/);
    expect(print).toMatch(/\.source-legend\s*\{[^}]*justify-content:\s*flex-start/);
  });
});

describe('small-screen layout', () => {
  test('shrinks the page and source insets together', () => {
    const narrow = mediaBlock(NARROW);
    expect(declaration('body', 'padding', narrow)).toBe('var(--sp-3)');
    expect(declaration('.source-dialog__header', 'padding', narrow)).toBe(declaration('body', 'padding', narrow));
  });

  test('swaps the group tabs for the group picker', () => {
    const narrow = mediaBlock(NARROW);
    expect(declaration('.group_picker', 'display')).toBe('none');
    expect(declaration('.group_picker', 'display', narrow)).toBe('block');
    expect(declaration('.group_picker + .group_tabs', 'display', narrow)).toBe('none');
  });

  test('shows the toggles as icons, keeping the words for screen readers', () => {
    const narrow = mediaBlock(NARROW);
    expect(declaration('.toolbar-toggle__label', 'position', narrow)).toBe('absolute');
    expect(declaration('.toolbar-toggle__label', 'clip-path', narrow)).toBe('inset(50%)');
    expect(narrow).not.toMatch(/\.toolbar-toggle__label\s*\{[^}]*display:\s*none/);
  });

  test('sizes the icon toggles to match the close button', () => {
    const narrow = mediaBlock(NARROW);
    expect(declaration('.toolbar-toggle', 'width', narrow)).toBe('var(--source-close-size)');
    expect(declaration('.toolbar-toggle', 'height', narrow)).toBe('var(--source-close-size)');
    expect(declaration('.toolbar-toggle', 'padding', narrow)).toBe('0');
  });

  test('drops the circles and highlights around the header buttons', () => {
    const narrow = mediaBlock(NARROW);
    const buttons = [
      '.toolbar-toggle',
      '.toolbar-toggle:hover',
      '.toolbar-toggle[aria-pressed="true"]',
      '.source-dialog__close',
      '.source-dialog__close:hover'
    ].join(',\n  ');
    expect(declaration(buttons, 'border-color', narrow)).toBe('transparent');
    expect(declaration(buttons, 'background', narrow)).toBe('transparent');
  });

  test('draws the close cross as tall as the emoji icons beside it', () => {
    const narrow = mediaBlock(NARROW);
    expect(declaration('.source-dialog__close::before,\n  .source-dialog__close::after', 'width', narrow)).toBe('18px');
  });

  test('shifts the crescent moon left so its weight sits on the button center', () => {
    const narrow = mediaBlock(NARROW);
    expect(declaration('.toolbar-toggle__icon--moon', 'position', narrow)).toBe('relative');
    expect(declaration('.toolbar-toggle__icon--moon', 'left', narrow)).toBe('-0.18em');
  });

  test('greys out the colorblind icon while the mode is off', () => {
    const narrow = mediaBlock(NARROW);
    expect(declaration('.toolbar-toggle[aria-pressed="false"]', 'filter', narrow)).toBe('grayscale(1)');
    expect(declaration('.toolbar-toggle[aria-pressed="false"]', 'opacity', narrow)).toBe('0.6');
  });

  test('spaces the icon toggles as far apart as the close button', () => {
    const narrow = mediaBlock(NARROW);
    expect(declaration('.toolbar,\n  .source-dialog__toggles', 'gap', narrow)).toBe('var(--source-close-gap)');
  });

  test('stacks the source header so the file name gets the full width', () => {
    const narrow = mediaBlock(NARROW);
    expect(declaration('.source-legend', 'grid-column', narrow)).toBe('1 / -1');
    const summaries = ['line', 'branch', 'method'].map((type) => `.source-dialog__title .t-${type}-summary`);
    expect(declaration(summaries.join(',\n  '), 'grid-column', narrow)).toBe('1 / -1');
    expect(declaration('.source-dialog__title h2', 'word-break', narrow)).toBe('normal');
  });

  test('scrolls the header and footer away with the source on small or short screens', () => {
    const small = mediaBlock(SMALL);
    expect(declaration('dialog.source-dialog[open]', 'display', small)).toBe('block');
    expect(declaration('dialog.source-dialog', 'overflow-y', small)).toBe('auto');
    expect(declaration('.source-dialog__body', 'overflow', small)).toBe('visible');
  });

  test('scales source code so 80 columns, line numbers and a hit count fit the width', () => {
    const fit = mediaBlock(FIT_SOURCE);
    expect(declaration('.source-dialog__body', 'container-type', fit)).toBe('inline-size');
    expect(declaration('.source_table pre', 'font-size', fit))
      .toBe('min(16px, (100cqw - 5px) / (var(--source-columns) * 0.61))');
    expect(declaration(':root', '--source-columns', fit)).toBe('91');
    expect(declaration('.source_table pre li::before', 'min-width', fit)).toBe('4ch');
    expect(declaration('.source_table pre li::before', 'padding', fit)).toBe('0 0.5ch');
    expect(declaration('.source_table pre li code', 'padding', fit)).toBe('0 1ch');
    expect(declaration('.source_table pre .hits', 'font-size', fit)).toBe('1em');
    expect(declaration('.source_table pre .hits', 'padding', fit)).toBe('0 0.5ch');
  });

  test('stops mobile browsers from inflating text', () => {
    expect(declaration('html', 'text-size-adjust')).toBe('100%');
  });
});
