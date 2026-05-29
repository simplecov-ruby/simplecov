// Pure formatting helpers: coverage-band CSS classes, number/percent
// formatting, stable HTML ids, relative timestamps, and per-file id hashing.

import { hash } from './hash';

const GREEN_THRESHOLD = 90;
const YELLOW_THRESHOLD = 75;

export function pctClass(pct: number): string {
  if (pct >= GREEN_THRESHOLD) return 'green';
  if (pct >= YELLOW_THRESHOLD) return 'yellow';
  return 'red';
}

export function fmtNum(n: number): string {
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

export function fmtPct(pct: number): string {
  return (Math.floor(pct * 100) / 100).toFixed(2);
}

// Build a stable, unique HTML id / CSS class name from a group title.
// The id is used in three places: the container `<div id="...">`, the
// tab `<a>`'s `className`, and a `.group_tabs a.<id>` CSS selector — so
// the result must be a valid CSS class name (ASCII letters/digits, plus
// `_` / `-`, not starting with a digit).
//
// The previous implementation stripped EVERY non-letter prefix and then
// every remaining non-alphanumeric char, which collapsed distinct titles
// like ">100LOC" and "<10LOC" into the same id ("LOC") — both containers
// got the same DOM id and the tabs rendered to one effective group. See
// #1038. A naive substitution (`> → _`, `< → _`) still loses uniqueness
// for any pair that differs only in which non-id char they use, so each
// non-id char is encoded as `_<hex codepoint>_` instead. Prefix with `g-`
// so the result always starts with a letter regardless of the original
// title.
export function toHtmlId(value: string): string {
  return 'g-' + value.replace(/[^a-zA-Z0-9_-]/gu, (c) => `_${c.codePointAt(0)!.toString(16)}_`);
}

// --- Timeago --------------------------------------------------

// Thresholds in seconds and their display unit.  Ordered largest-first so
// the first match wins.
const TIMEAGO_INTERVALS: [number, string][] = [
  [31536000, 'year'], [2592000, 'month'], [86400, 'day'],
  [3600, 'hour'], [60, 'minute'], [1, 'second']
];

export function timeago(date: Date): string {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  for (const [secs, label] of TIMEAGO_INTERVALS) {
    const count = Math.floor(seconds / secs);
    if (count >= 1) {
      return count === 1 ? `about 1 ${label} ago` : `${count} ${label}s ago`;
    }
  }
  return 'just now';
}

// Returns the number of milliseconds until the displayed timeago text would
// change for the given date.  For example, if "3 minutes ago" is displayed,
// the text won't change until the 4th minute boundary, so we return the
// remaining ms until that boundary (plus a small buffer).
export function timeagoNextTick(date: Date): number {
  const elapsedSec = (Date.now() - date.getTime()) / 1000;
  for (const [secs] of TIMEAGO_INTERVALS) {
    const count = Math.floor(elapsedSec / secs);
    if (count >= 1) {
      // The text will next change when elapsed reaches (count + 1) * secs
      const nextBoundary = (count + 1) * secs;
      // Add 500ms buffer so we land just after the boundary, not right on it
      return Math.max((nextBoundary - elapsedSec) * 1000 + 500, 1000);
    }
  }
  // Currently "just now" — update in 1 second (when it becomes "1 second ago")
  return 1000;
}

// --- Per-file ids ---------------------------------------------

// Populated by precomputeFileIds before any rendering happens.
const fileIds: Record<string, string> = {};

export function fileId(filename: string): string {
  return fileIds[filename];
}

export async function precomputeFileIds(filenames: string[]): Promise<void> {
  const hashes = await Promise.all(filenames.map(hash));
  filenames.forEach((fn, i) => { fileIds[fn] = hashes[i]; });
}
