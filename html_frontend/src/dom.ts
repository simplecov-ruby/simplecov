// Tiny DOM helpers shared across the report's modules.

export function $(sel: string, ctx?: Element | Document): Element | null {
  return (ctx || document).querySelector(sel);
}

export function $$(sel: string, ctx?: Element | Document): Element[] {
  return Array.from((ctx || document).querySelectorAll(sel));
}

export function on(
  target: EventTarget,
  event: string,
  selectorOrFn: string | ((e: Event) => void),
  fn?: (this: Element, e: Event) => void
): void {
  if (typeof selectorOrFn === 'function') {
    target.addEventListener(event, selectorOrFn);
  } else {
    target.addEventListener(event, function (e: Event) {
      const el = (e.target as Element).closest(selectorOrFn);
      if (el && (target as Element).contains(el) && fn) {
        fn.call(el, e);
      }
    });
  }
}

const HTML_ESCAPES: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;'
};

export function escapeHTML(str: string): string {
  return str.replace(/[&<>"']/g, (char) => HTML_ESCAPES[char]);
}
