// The run-history sparklines: series building from history entries and
// the inline-SVG rendering — geometry, gap segmentation, band classing.
import { describe, expect, test } from 'bun:test';
import { fileTrendSeries, totalsTrendSeries, renderSparkline } from '../src/sparkline';
import type { HistoryEntry } from '../src/types';

function entry(overrides: Partial<HistoryEntry>): HistoryEntry {
  return { created_at: '2026-08-25T10:00:00Z', ...overrides };
}

describe('fileTrendSeries', () => {
  test('builds one series per file across every entry, gaps where a run missed it', () => {
    const series = fileTrendSeries([
      entry({ files: { 'lib/a.rb': 50, 'lib/b.rb': 80 } }),
      entry({ files: { 'lib/a.rb': 75 } }),
      entry({ files: { 'lib/a.rb': 100, 'lib/b.rb': 90 } })
    ]);

    expect(series.get('lib/a.rb')).toEqual([50, 75, 100]);
    expect(series.get('lib/b.rb')).toEqual([80, null, 90]);
  });

  test('tolerates entries without a files table', () => {
    const series = fileTrendSeries([entry({}), entry({ files: { 'lib/a.rb': 100 } })]);
    expect(series.get('lib/a.rb')).toEqual([null, 100]);
  });
});

describe('totalsTrendSeries', () => {
  const history = [
    entry({ totals: { line: 90 }, groups: { Models: { line: 70 } } }),
    entry({ totals: { line: 95 } }),
    entry({ totals: { line: 100 }, groups: { Models: { line: 80 } } })
  ];

  test('reads the report totals for the null group', () => {
    expect(totalsTrendSeries(history, null, 'line')).toEqual([90, 95, 100]);
  });

  test("reads a named group's totals, gaps where the group was unrecorded", () => {
    expect(totalsTrendSeries(history, 'Models', 'line')).toEqual([70, null, 80]);
  });

  test('gaps a criterion the entry did not measure', () => {
    expect(totalsTrendSeries(history, null, 'branch')).toEqual([null, null, null]);
  });
});

describe('renderSparkline', () => {
  test('renders a polyline with the newest run as a band-colored dot', () => {
    const svg = renderSparkline([90, 95, 100]);

    expect(svg).toContain('class="sparkline green"');
    expect(svg).toContain('<polyline points="3,19 42,11 81,3"></polyline>');
    expect(svg).toContain('<circle class="sparkline__now" cx="81" cy="3" r="2"></circle>');
    expect(svg).toContain('<title>3 runs: 90.00% to 100.00%</title>');
    expect(svg).toContain('aria-label="3 runs: 90.00% to 100.00%"');
  });

  test('classes the dot by the current band', () => {
    expect(renderSparkline([90, 60])).toContain('class="sparkline red"');
    expect(renderSparkline([60, 80])).toContain('class="sparkline yellow"');
  });

  test('breaks the line at gaps instead of interpolating, lone points as dots', () => {
    const svg = renderSparkline([50, null, 100, 100]);

    expect(svg).toContain('<circle class="sparkline__lone" cx="3" cy="19" r="1.5"></circle>');
    expect(svg).toContain('<polyline points="55,3 81,3"></polyline>');
  });

  test('draws a flat series at mid height', () => {
    expect(renderSparkline([80, 80])).toContain('points="3,11 81,11"');
  });

  test('renders nothing for a series without direction', () => {
    expect(renderSparkline([])).toBe('');
    expect(renderSparkline([100])).toBe('');
    expect(renderSparkline([null, 100])).toBe('');
  });
});
