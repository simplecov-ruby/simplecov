
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
// through p*4+4.
export function decodeFileContexts(
  tables: Record<string, string> | undefined,
  lineCount: number
): FileContextIndex {
  const perLine: number[][] = Array.from({ length: lineCount }, () => []);

  const indices = Object.keys(tables || {}).map(Number).sort((a, b) => a - b);
  for (const contextIndex of indices) {
    const hex = tables![String(contextIndex)];
    for (let p = 0; p < hex.length; p++) {
      const nibble = parseInt(hex[hex.length - 1 - p], 16);
      if (nibble === 0) continue;
      for (let bit = 0; bit < 4; bit++) {
        if (!(nibble & (1 << bit))) continue;
        const lineIndex = p * 4 + bit;
        if (lineIndex < lineCount) perLine[lineIndex].push(contextIndex);
      }
    }
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

  const union: number[] = [];
  for (const hex of Object.values(tables || {})) {
    for (let p = 0; p < hex.length; p++) {
      union[p] = (union[p] || 0) | parseInt(hex[hex.length - 1 - p], 16);
    }
  }

  let outside = 0;
  for (let i = 0; i < lines.length; i++) {
    const cov = lines[i];
    if (typeof cov !== 'number' || cov <= 0) continue;
    if (!((union[i >> 2] || 0) & (1 << (i & 3)))) outside++;
  }
  return outside;
}

// Deliberately the same answer, in the same order, that
// `simplecov tests <file>:<line>` prints.
export function contextIdsForLine(index: FileContextIndex, contexts: string[], line: number): string[] {
  const entries = index.perLine[line - 1];
  if (!entries) return [];
  return entries.map((i) => contexts[i]).sort();
}
