import { describe, expect, test } from 'bun:test';
import { decodeFileContexts, contextIdsForLine, coveredOutsideCount } from '../src/contexts';

describe('decodeFileContexts', () => {
  test('decodes a single-context hex bitmap into per-line context indices', () => {
    // 0x6 = 0b110: bits 1 and 2 set, so lines 2 and 3.
    const index = decodeFileContexts({ '0': '6' }, 4);
    expect(index.perLine[0]).toEqual([]);
    expect(index.perLine[1]).toEqual([0]);
    expect(index.perLine[2]).toEqual([0]);
    expect(index.perLine[3]).toEqual([]);
  });

  test('walks multi-nibble bitmaps with the least significant nibble as lines 1-4', () => {
    // 0x100 = bit 8, so line 9 only.
    const index = decodeFileContexts({ '2': '100' }, 9);
    expect(index.perLine[8]).toEqual([2]);
    expect(index.perLine.slice(0, 8).every((l) => l.length === 0)).toBe(true);
  });

  test('accumulates overlapping contexts in index order', () => {
    const index = decodeFileContexts({ '1': '4', '0': '6' }, 3);
    // Line 3 (bit 2) is covered by both; order is ascending by index.
    expect(index.perLine[2]).toEqual([0, 1]);
    expect(index.perLine[1]).toEqual([0]);
  });

  test('ignores bits beyond the file length rather than growing the table', () => {
    const index = decodeFileContexts({ '0': 'ff' }, 3);
    expect(index.perLine.length).toBe(3);
    expect(index.perLine[2]).toEqual([0]);
  });

  test('treats an absent table as an untouched file, not as unrecorded', () => {
    const index = decodeFileContexts(undefined, 2);
    expect(index.perLine).toEqual([[], []]);
  });
});

describe('contextIdsForLine', () => {
  const contexts = ['spec/b_spec.rb:9', 'spec/a_spec.rb:12'];

  test('resolves a line\'s indices to sorted ids, matching the CLI\'s answer', () => {
    const index = decodeFileContexts({ '0': '1', '1': '1' }, 1);
    expect(contextIdsForLine(index, contexts, 1)).toEqual(['spec/a_spec.rb:12', 'spec/b_spec.rb:9']);
  });

  test('answers an empty list for an uncovered or out-of-range line', () => {
    const index = decodeFileContexts({ '0': '1' }, 2);
    expect(contextIdsForLine(index, contexts, 2)).toEqual([]);
    expect(contextIdsForLine(index, contexts, 99)).toEqual([]);
  });
});

describe('coveredOutsideCount', () => {
  test('counts covered relevant lines no recorded context executed', () => {
    // 0xb = bits 0,1,3 -> lines 1, 2, 4. Line 4 is non-executable, so the
    // recorded lines that matter are 1 and 2; lines 3 and 5 are covered
    // with no context.
    const lines = [1, 2, 3, null, 4, 0, 'ignored' as const];
    expect(coveredOutsideCount({ '0': 'b' }, lines)).toBe(2);
  });

  test('unions every context before counting', () => {
    const lines = [1, 1, 1];
    expect(coveredOutsideCount({ '0': '1', '2': '4' }, lines)).toBe(1);
  });

  test('treats an absent table as a file no test touched', () => {
    expect(coveredOutsideCount(undefined, [1, 0, 5, null])).toBe(2);
  });

  test('returns 0 without line data', () => {
    expect(coveredOutsideCount({ '0': '1' }, undefined)).toBe(0);
  });
});
