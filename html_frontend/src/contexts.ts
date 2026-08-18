// Decoding for the per-test context data recorded under `track_tests`:
// the document carries a `contexts` array of test ids, and each file entry
// may carry a table of hex bitmaps keyed by context index, where bit N set
// means source line N+1 was executed by that context (see the coverage.json
// schema, version 1.1).

export interface FileContextIndex {
  // Index i holds the (ascending) context indices that executed line i+1.
  perLine: number[][];
  // How many distinct recorded contexts touched this file at all.
  distinct: number;
}

// Turns one file's bitmap table into a per-line index. An absent table is
// an untouched file, not an unrecorded run: whether recording happened at
// all is the document-level `contexts` array's presence, which callers
// gate on before decoding anything.
export function decodeFileContexts(
  tables: Record<string, string> | undefined,
  lineCount: number
): FileContextIndex {
  const perLine: number[][] = Array.from({ length: lineCount }, () => []);
  let distinct = 0;

  // Ascending context order keeps each line's list deterministic no matter
  // the table's key order.
  const indices = Object.keys(tables || {}).map(Number).sort((a, b) => a - b);
  for (const contextIndex of indices) {
    distinct++;
    const hex = tables![String(contextIndex)];
    // Walk nibbles from the least significant end: hex digit p (from the
    // right) carries lines p*4+1 through p*4+4.
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

  return { perLine, distinct };
}

// The ids covering `line`, sorted — deliberately the same answer, in the
// same order, that `simplecov tests <file>:<line>` prints.
export function contextIdsForLine(index: FileContextIndex, contexts: string[], line: number): string[] {
  const entries = index.perLine[line - 1];
  if (!entries) return [];
  return entries.map((i) => contexts[i]).sort();
}
