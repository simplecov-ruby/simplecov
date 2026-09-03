import { describe, expect, test } from 'bun:test';
import { decodeFileContexts, contextIdsForLine, coveredOutsideCount } from '../src/contexts';

describe('decodeFileContexts', () => {
  test('decodes a single-context hex bitmap into per-line context indices', () => {
    const index = decodeFileContexts({ '0': '6' }, 4);
    expect(index.perLine[0]).toEqual([]);
    expect(index.perLine[1]).toEqual([0]);
    expect(index.perLine[2]).toEqual([0]);
    expect(index.perLine[3]).toEqual([]);
  });

  test('walks multi-nibble bitmaps with the least significant nibble as lines 1-4', () => {
    const index = decodeFileContexts({ '2': '100' }, 9);
    expect(index.perLine[8]).toEqual([2]);
    expect(index.perLine.slice(0, 8).every((l) => l.length === 0)).toBe(true);
  });

  test('accumulates overlapping contexts in index order', () => {
    const index = decodeFileContexts({ '1': '4', '0': '6' }, 3);
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

describe('coveredOutsideCount bit placement', () => {
  test('a context covering only line 2 leaves line 1 outside', () => {
    expect(coveredOutsideCount({ '0': '2' }, [1, 1])).toBe(1);
  });

  test('reads multi-digit bitmaps from the least significant nibble', () => {
    expect(coveredOutsideCount({ '0': '10' }, [1, 0, 0, 0, null])).toBe(1);
    expect(coveredOutsideCount({ '0': '10' }, [null, 0, 0, 0, 1])).toBe(0);
  });
});
