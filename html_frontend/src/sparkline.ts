// Sparklines over the run history: direction of travel drawn as a quiet
// line in the report's secondary ink, with the newest run as a dot in
// the file's own coverage-band color — the trend is context, the current
// state is the verdict, and both speak the palette the report already
// uses (so dark mode and the colorblind toggle need nothing new).
//
// Series are min-max scaled: direction is the message, and the tooltip
// carries the absolute numbers. Runs with no recorded value break the
// line into segments rather than being interpolated over.

import { fmtPct, pctClass } from './format';
import type { HistoryEntry } from './types';

const WIDTH = 84;
const HEIGHT = 22;
const PAD = 3;

// One value per recorded run, oldest first; null where the run recorded
// nothing for the series' subject.
export type Series = (number | null)[];

export interface TrendData {
  totals: Series;
  files: Map<string, Series>;
}

// Per-file series across the whole history, built once and shared by
// every group's file list.
export function fileTrendSeries(history: HistoryEntry[]): Map<string, Series> {
  const names = new Set<string>();
  for (const entry of history) {
    for (const name of Object.keys(entry.files || {})) names.add(name);
  }
  const series = new Map<string, Series>();
  for (const name of names) {
    series.set(name, history.map((entry) => numeric(entry.files?.[name])));
  }
  return series;
}

// The totals series for one group (or, with null, the whole report),
// on the report's primary criterion.
export function totalsTrendSeries(history: HistoryEntry[], groupName: string | null, primary: string): Series {
  return history.map((entry) => {
    const totals = groupName === null ? entry.totals : entry.groups?.[groupName];
    return numeric(totals?.[primary]);
  });
}

// The inline SVG for one series, or '' when there is not enough data
// for a direction (under two recorded points).
export function renderSparkline(series: Series): string {
  const values = series.filter((value): value is number => value !== null);
  if (values.length < 2) return '';

  const points = plot(series);
  const segments = segment(points);
  const current = values[values.length - 1];
  const label = `${values.length} runs: ${fmtPct(values[0])}% to ${fmtPct(current)}%`;

  const parts = [
    `<svg class="sparkline ${pctClass(current)}" viewBox="0 0 ${WIDTH} ${HEIGHT}" role="img" aria-label="${label}">`,
    `<title>${label}</title>`
  ];
  for (const seg of segments) {
    if (seg.length === 1) {
      parts.push(`<circle class="sparkline__lone" cx="${seg[0].x}" cy="${seg[0].y}" r="1.5"></circle>`);
    } else {
      parts.push(`<polyline points="${seg.map((p) => `${p.x},${p.y}`).join(' ')}"></polyline>`);
    }
  }
  const now = points[points.length - 1];
  parts.push(`<circle class="sparkline__now" cx="${now.x}" cy="${now.y}" r="2"></circle>`, '</svg>');
  return parts.join('');
}

interface Point { x: number; y: number; gapBefore: boolean }

// Scale the series into the viewBox. A flat series sits at mid height:
// a flat line is the message, not a division by zero.
function plot(series: Series): Point[] {
  const values = series.filter((value): value is number => value !== null);
  const min = Math.min(...values);
  const span = Math.max(...values) - min;
  const step = series.length > 1 ? (WIDTH - PAD * 2) / (series.length - 1) : 0;

  const points: Point[] = [];
  let gapBefore = false;
  series.forEach((value, index) => {
    if (value === null) {
      gapBefore = true;
      return;
    }
    const y = span === 0 ? HEIGHT / 2 : HEIGHT - PAD - ((value - min) / span) * (HEIGHT - PAD * 2);
    points.push({ x: round(PAD + index * step), y: round(y), gapBefore });
    gapBefore = false;
  });
  return points;
}

function segment(points: Point[]): Point[][] {
  const segments: Point[][] = [];
  for (const point of points) {
    if (point.gapBefore || segments.length === 0) segments.push([]);
    segments[segments.length - 1].push(point);
  }
  return segments;
}

function round(value: number): number {
  return Math.round(value * 10) / 10;
}

function numeric(value: unknown): number | null {
  return typeof value === 'number' ? value : null;
}
