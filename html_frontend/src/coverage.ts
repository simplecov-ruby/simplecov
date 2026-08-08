// Criterion selection shared by page summaries and file-list groups.

import type { CoverageData, CoverageStat, CoverageType, StatGroup } from './types';

export function normalizeCoverageType(value: string | undefined): CoverageType | undefined {
  if (value === 'oneshot_line') return 'line';
  if (value === 'line' || value === 'branch' || value === 'method') return value;
  return undefined;
}

export function activeCoverageType(meta: CoverageData['meta']): CoverageType {
  const primary = normalizeCoverageType(meta.primary_coverage);
  if (primary === 'line' && meta.line_coverage) return primary;
  if (primary === 'branch' && meta.branch_coverage) return primary;
  if (primary === 'method' && meta.method_coverage) return primary;
  if (meta.line_coverage) return 'line';
  if (meta.branch_coverage) return 'branch';
  return 'method';
}

export function coverageStat(stats: StatGroup, type: CoverageType): CoverageStat | undefined {
  if (type === 'line') return stats.lines;
  if (type === 'branch') return stats.branches;
  return stats.methods;
}

export function primaryCoverageStat(stats: StatGroup, primary: CoverageType): CoverageStat | undefined {
  return coverageStat(stats, primary) || stats.lines || stats.branches || stats.methods;
}
