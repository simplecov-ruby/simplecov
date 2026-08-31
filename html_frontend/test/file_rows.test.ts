import { beforeEach, describe, expect, test } from 'bun:test';
import { getVisibleFileRows, invalidateFileRowCache } from '../src/file_rows';

function buildContainers(): void {
  document.body.innerHTML = `
    <div class="file_list_container" style="display: none">
      <table><tbody><tr class="t-file" id="hidden-group-row"></tr></tbody></table>
    </div>
    <div class="file_list_container">
      <table><tbody>
        <tr class="t-file" id="row-1"></tr>
        <tr class="t-file" id="row-2" style="display: none"></tr>
        <tr class="t-file" id="row-3"></tr>
      </tbody></table>
    </div>`;
}

describe('getVisibleFileRows', () => {
  beforeEach(() => {
    invalidateFileRowCache();
  });

  test('returns the visible rows of the first visible container', () => {
    buildContainers();
    expect(getVisibleFileRows().map((r) => r.id)).toEqual(['row-1', 'row-3']);
  });

  test('returns an empty list when every container is hidden', () => {
    document.body.innerHTML =
      '<div class="file_list_container" style="display: none"></div>';
    expect(getVisibleFileRows()).toEqual([]);
  });

  test('serves the cached array until invalidated', () => {
    buildContainers();
    const first = getVisibleFileRows();
    document.getElementById('row-3')!.remove();
    expect(getVisibleFileRows()).toBe(first);

    invalidateFileRowCache();
    expect(getVisibleFileRows().map((r) => r.id)).toEqual(['row-1']);
  });
});
