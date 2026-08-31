
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
