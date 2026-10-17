import { $, $$ } from './dom';

export function setupGroupPicker(): void {
  const links = $$('.group_tabs li a') as HTMLAnchorElement[];
  if (links.length < 2) return;

  const select = document.createElement('select');
  select.className = 'group_picker';
  select.setAttribute('aria-label', 'Coverage group');
  for (const link of links) {
    const option = document.createElement('option');
    option.value = link.getAttribute('href')!.substring(1);
    option.textContent = link.textContent;
    option.selected = link.parentElement!.classList.contains('active');
    select.appendChild(option);
  }
  select.addEventListener('change', () => {
    window.location.hash = '#_' + select.value;
  });

  const strip = $('.group_tabs')!;
  strip.parentElement!.insertBefore(select, strip);
}

export function syncGroupPicker(tabId: string): void {
  const select = $('select.group_picker') as HTMLSelectElement | null;
  if (select) select.value = tabId;
}
