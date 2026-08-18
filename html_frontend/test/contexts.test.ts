import { describe, expect, test } from 'bun:test';
import { decodeFileContexts, contextIdsForLine } from '../src/contexts';

describe('decodeFileContexts', () => {
  test('decodes a single-context hex bitmap into per-line context indices', () => {
    // 0x6 = 0b110: bits 1 and 2 set, so lines 2 and 3.
    const index = decodeFileContexts({ '0': '6' }, 4);
    expect(index.perLine[0]).toEqual([]);
    expect(index.perLine[1]).toEqual([0]);
    expect(index.perLine[2]).toEqual([0]);
    expect(index.perLine[3]).toEqual([]);
    expect(index.distinct).toBe(1);
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
    expect(index.distinct).toBe(2);
  });

  test('ignores bits beyond the file length rather than growing the table', () => {
    const index = decodeFileContexts({ '0': 'ff' }, 3);
    expect(index.perLine.length).toBe(3);
    expect(index.perLine[2]).toEqual([0]);
  });

  test('treats an absent table as an untouched file, not as unrecorded', () => {
    const index = decodeFileContexts(undefined, 2);
    expect(index.perLine).toEqual([[], []]);
    expect(index.distinct).toBe(0);
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
