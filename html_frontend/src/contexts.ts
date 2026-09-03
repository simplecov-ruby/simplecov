
export interface FileContextIndex {
  perLine: number[][];
}

// Decoding for the per-test context data recorded under `track_tests`: the
// document carries a `contexts` array of test ids, and each file entry may
// carry a table of hex bitmaps keyed by context index, where bit N set means
// source line N+1 was executed by that context.
//
// An absent table is an untouched file, not an unrecorded run: whether
// recording happened at all is the document-level `contexts` array's presence,
// which callers gate on before decoding anything. Nibbles are walked from the
// least significant end, so hex digit p from the right carries lines p*4+1
// through p*4+4. Integer-like keys enumerate in ascending order, so each line's
// list comes out in context index order without sorting.
export function decodeFileContexts(
  tables: Record<string, string> | undefined,
  lineCount: number
): FileContextIndex {
  const perLine: number[][] = Array.from({ length: lineCount }, () => []);

  for (const [key, hex] of Object.entries(tables || {})) {
    const contextIndex = Number(key);
    Array.from(hex).reverse().forEach((digit, p) => {
      const nibble = parseInt(digit, 16);
      for (const bit of [0, 1, 2, 3]) {
        if (!(nibble & (1 << bit))) continue;
        const lineIndex = p * 4 + bit;
        if (lineIndex < lineCount) perLine[lineIndex].push(contextIndex);
      }
    });
  }

  return { perLine };
}

// How many relevant covered lines no recorded context executed. This one number
// is the fact behind both the file list's grey bar share and the source header's
// "covered outside tests" figure. It works on the raw bitmaps rather than a
// decoded per-line index, since the file list pays this for every file on load.
export function coveredOutsideCount(
  tables: Record<string, string> | undefined,
  lines: (number | null | 'ignored')[] | undefined
): number {
  if (!lines) return 0;

  // Stryker disable next-line ArrayDeclaration: a type error TypeScript 7 cannot report to Stryker, and a string ORs as 0
  const union: number[] = [];
  for (const hex of Object.values(tables || {})) {
    Array.from(hex).reverse().forEach((digit, p) => {
      union[p] = (union[p] || 0) | parseInt(digit, 16);
    });
  }

  let outside = 0;
  lines.forEach((cov, i) => {
    if (typeof cov !== 'number' || cov <= 0) return;
    if (!((union[i >> 2] || 0) & (1 << (i & 3)))) outside++;
  });
  return outside;
}

// Deliberately the same answer, in the same order, that
// `simplecov tests <file>:<line>` prints.
export function contextIdsForLine(index: FileContextIndex, contexts: string[], line: number): string[] {
  const entries = index.perLine[line - 1];
  if (!entries) return [];
  return entries.map((i) => contexts[i]).sort();
}
