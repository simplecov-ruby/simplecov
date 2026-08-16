// Bitmap decoding for per-test contexts: bit N-1 of a file's hex bitmap
// set means line N was executed by that test.
import { describe, expect, test } from 'bun:test';
import { bitmapCoversLine, testCountsPerLine, testsCoveringLine } from '../src/test_contexts';

describe('bitmapCoversLine', () => {
  test('reads bits inside the last nibble', () => {
    expect(bitmapCoversLine('1', 1)).toBe(true);
    expect(bitmapCoversLine('2', 2)).toBe(true);
    expect(bitmapCoversLine('2', 1)).toBe(false);
    expect(bitmapCoversLine('8', 4)).toBe(true);
  });

  test('crosses nibble boundaries in a multi-character bitmap', () => {
    // 0xff3 = lines 1, 2 and 5..12
    expect(bitmapCoversLine('ff3', 1)).toBe(true);
    expect(bitmapCoversLine('ff3', 3)).toBe(false);
    expect(bitmapCoversLine('ff3', 5)).toBe(true);
    expect(bitmapCoversLine('ff3', 12)).toBe(true);
    expect(bitmapCoversLine('ff3', 13)).toBe(false);
  });

  test('answers false past the end of the bitmap', () => {
    expect(bitmapCoversLine('1', 5)).toBe(false);
    expect(bitmapCoversLine('', 1)).toBe(false);
  });
});

describe('testCountsPerLine', () => {
  test('sums covering tests per line', () => {
    // test 0 covers lines 1-2 (0x3), test 1 covers lines 2 and 5 (0x12)
    const counts = testCountsPerLine({'0': '3', '1': '12'}, 6);
    expect(counts).toEqual([1, 2, 0, 0, 1, 0]);
  });

  test('ignores bits beyond the file length', () => {
    expect(testCountsPerLine({'0': 'ff'}, 3)).toEqual([1, 1, 1]);
  });

  test('answers zeros for an empty map', () => {
    expect(testCountsPerLine({}, 2)).toEqual([0, 0]);
  });
});

describe('testsCoveringLine', () => {
  test('returns the numerically-sorted indices of the covering tests', () => {
    const contexts = {'10': '2', '2': '2', '0': '1'};
    expect(testsCoveringLine(contexts, 2)).toEqual([2, 10]);
    expect(testsCoveringLine(contexts, 1)).toEqual([0]);
    expect(testsCoveringLine(contexts, 3)).toEqual([]);
  });
});
