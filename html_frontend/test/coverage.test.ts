import { describe, expect, test } from 'bun:test';
import {
  activeCoverageType,
  coverageStat,
  normalizeCoverageType,
  primaryCoverageStat
} from '../src/coverage';
import type { CoverageData, CoverageStat, StatGroup } from '../src/types';

function makeMeta(overrides: Partial<CoverageData['meta']> = {}): CoverageData['meta'] {
  return {
    simplecov_version: '0.23.1',
    command_name: 'RSpec',
    project_name: 'Sample Project',
    timestamp: '2026-08-11T00:00:00+00:00',
    root: '/project',
    line_coverage: true,
    branch_coverage: false,
    method_coverage: false,
    ...overrides
  };
}

function stat(covered: number): CoverageStat {
  return {covered, missed: 0, total: covered, percent: 100, strength: 1};
}

describe('normalizeCoverageType', () => {
  test('maps oneshot_line onto line', () => {
    expect(normalizeCoverageType('oneshot_line')).toBe('line');
  });

  test('passes the three known criteria through', () => {
    expect(normalizeCoverageType('line')).toBe('line');
    expect(normalizeCoverageType('branch')).toBe('branch');
    expect(normalizeCoverageType('method')).toBe('method');
  });

  test('rejects unknown and missing values', () => {
    expect(normalizeCoverageType('bogus')).toBeUndefined();
    expect(normalizeCoverageType(undefined)).toBeUndefined();
  });
});

describe('activeCoverageType', () => {
  test('honors the configured primary criterion when it is enabled', () => {
    expect(activeCoverageType(makeMeta({primary_coverage: 'line'}))).toBe('line');
    expect(activeCoverageType(makeMeta({primary_coverage: 'branch', branch_coverage: true}))).toBe('branch');
    expect(activeCoverageType(makeMeta({primary_coverage: 'method', method_coverage: true}))).toBe('method');
  });

  test('falls back when the primary criterion is disabled', () => {
    expect(activeCoverageType(makeMeta({primary_coverage: 'branch'}))).toBe('line');
  });

  test('defaults to the first enabled criterion without a primary', () => {
    expect(activeCoverageType(makeMeta())).toBe('line');
    expect(activeCoverageType(makeMeta({line_coverage: false, branch_coverage: true}))).toBe('branch');
    expect(activeCoverageType(makeMeta({line_coverage: false, method_coverage: true}))).toBe('method');
  });
});

describe('coverageStat', () => {
  const stats: StatGroup = {lines: stat(1), branches: stat(2), methods: stat(3)};

  test('selects the stat block matching the criterion', () => {
    expect(coverageStat(stats, 'line')).toBe(stats.lines);
    expect(coverageStat(stats, 'branch')).toBe(stats.branches);
    expect(coverageStat(stats, 'method')).toBe(stats.methods);
  });
});

describe('primaryCoverageStat', () => {
  test('prefers the primary criterion when present', () => {
    const stats: StatGroup = {lines: stat(1), branches: stat(2)};
    expect(primaryCoverageStat(stats, 'branch')).toBe(stats.branches);
  });

  test('walks the lines/branches/methods fallback chain', () => {
    const branchesOnly: StatGroup = {branches: stat(2)};
    expect(primaryCoverageStat(branchesOnly, 'method')).toBe(branchesOnly.branches);
    const methodsOnly: StatGroup = {methods: stat(3)};
    expect(primaryCoverageStat(methodsOnly, 'line')).toBe(methodsOnly.methods);
    expect(primaryCoverageStat({}, 'line')).toBeUndefined();
  });
});
