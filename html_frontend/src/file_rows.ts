// Cache of the currently-visible file rows in the active group. Shared by the
// table (which invalidates it after filtering) and the viewer's keyboard
// navigation (which iterates it). Kept in its own module so neither depends on
// the other.

import { $$ } from './dom';

let cachedFileRows: HTMLElement[] | null = null;

export function invalidateFileRowCache(): void {
  cachedFileRows = null;
}

export function getVisibleFileRows(): HTMLElement[] {
  if (cachedFileRows) return cachedFileRows;
  const visible = $$('.file_list_container').filter(c => (c as HTMLElement).style.display !== 'none');
  if (!visible.length) return [];
  cachedFileRows = $$('tbody tr.t-file', visible[0]).filter(r => (r as HTMLElement).style.display !== 'none') as HTMLElement[];
  return cachedFileRows;
}
