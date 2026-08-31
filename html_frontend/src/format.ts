
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

export function toHtmlId(value: string): string {
  return 'g-' + value.replace(/[^a-zA-Z0-9-]/gu, (c) => `_${c.codePointAt(0)!.toString(16)}_`);
}


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

export function timeagoNextTick(date: Date): number {
  const elapsedSec = (Date.now() - date.getTime()) / 1000;
  for (const [secs] of TIMEAGO_INTERVALS) {
    const count = Math.floor(elapsedSec / secs);
    if (count >= 1) {
      const nextBoundary = (count + 1) * secs;
      return Math.max((nextBoundary - elapsedSec) * 1000 + 500, 1000);
    }
  }
  return 1000;
}


const fileIds = new Map<string, string>();

export function fileId(filename: string): string {
  const id = fileIds.get(filename);
  if (id === undefined) throw new Error(`File ID was not precomputed for ${filename}`);
  return id;
}

export async function precomputeFileIds(filenames: string[]): Promise<void> {
  fileIds.clear();
  const uniqueFilenames = [...new Set(filenames)];
  const hashes = await Promise.all(uniqueFilenames.map(hash));
  const buckets = new Map<string, string[]>();

  uniqueFilenames.forEach((filename, index) => {
    const baseId = hashes[index];
    const bucket = buckets.get(baseId) || [];
    bucket.push(filename);
    buckets.set(baseId, bucket);
  });

  for (const [baseId, bucket] of buckets) {
    bucket.sort().forEach((filename, index) => {
      fileIds.set(filename, index === 0 ? baseId : `${baseId}-${index}`);
    });
  }
}
