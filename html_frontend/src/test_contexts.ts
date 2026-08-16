// Pure decoding of per-test context bitmaps: each file carries a map from
// test index (a decimal string into meta.test_contexts.tests) to a lowercase
// hex bitmap of the lines that test executed, bit N-1 meaning line N.

export function bitmapCoversLine(hex: string, line: number): boolean {
  const nibbleIndex = (line - 1) >> 2;
  const charIndex = hex.length - 1 - nibbleIndex;
  if (charIndex < 0) return false;
  const nibble = parseInt(hex[charIndex], 16);
  return (nibble & (1 << ((line - 1) & 3))) !== 0;
}

export function testsCoveringLine(contexts: Record<string, string>, line: number): number[] {
  const indices: number[] = [];
  for (const key of Object.keys(contexts)) {
    if (bitmapCoversLine(contexts[key], line)) indices.push(Number(key));
  }
  return indices.sort((a, b) => a - b);
}

/** How many tests cover each line; index N is line N+1. */
export function testCountsPerLine(contexts: Record<string, string>, lineCount: number): number[] {
  const counts = new Array<number>(lineCount).fill(0);
  for (const hex of Object.values(contexts)) {
    for (let nibbleIndex = 0; nibbleIndex < hex.length; nibbleIndex++) {
      const nibble = parseInt(hex[hex.length - 1 - nibbleIndex], 16);
      if (!nibble) continue;
      for (let bit = 0; bit < 4; bit++) {
        if (nibble & (1 << bit)) {
          const lineIndex = nibbleIndex * 4 + bit;
          if (lineIndex < lineCount) {
            counts[lineIndex]++;
          }
        }
      }
    }
  }
  return counts;
}
