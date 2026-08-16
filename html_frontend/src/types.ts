// Shared types for the coverage report data (the JSON shape emitted by the
// Ruby JSONFormatter and assigned to `window.SIMPLECOV_DATA`).

export interface CoverageData {
  meta: {
    simplecov_version: string;
    command_name: string;
    project_name: string;
    timestamp: string;
    root: string;
    primary_coverage?: string;
    line_coverage: boolean;
    branch_coverage: boolean;
    method_coverage: boolean;
    test_contexts?: TestContextsMeta;
  };
  total: StatGroup;
  coverage: Record<string, FileCoverage>;
  groups: Record<string, GroupData>;
}

export type CoverageType = 'line' | 'branch' | 'method';

export interface TestContextEntry {
  id: string;
  name: string;
}

export interface TestContextsMeta {
  granularity: 'per_test';
  tests: TestContextEntry[];
}

export interface StatGroup {
  lines?: CoverageStat;
  branches?: CoverageStat;
  methods?: CoverageStat;
}

export interface CoverageStat {
  covered: number;
  missed: number;
  total: number;
  percent: number;
  strength: number;
}

export interface FileCoverage {
  lines?: (number | null | 'ignored')[];
  source: string[];
  lines_covered_percent?: number;
  covered_lines?: number;
  missed_lines?: number;
  total_lines?: number;
  branches?: BranchEntry[];
  branches_covered_percent?: number;
  covered_branches?: number;
  missed_branches?: number;
  total_branches?: number;
  methods?: MethodEntry[];
  methods_covered_percent?: number;
  covered_methods?: number;
  missed_methods?: number;
  total_methods?: number;
  /**
   * Test index (decimal string into meta.test_contexts.tests) -> lowercase
   * hex bitmap; bit N-1 set = line N covered by that test. Present on every
   * file if and only if the report recorded per-test contexts.
   */
  test_contexts?: Record<string, string>;
}

export interface BranchEntry {
  type: string;
  start_line: number;
  end_line: number;
  coverage: number | 'ignored';
  inline: boolean;
  report_line: number;
}

export interface MethodEntry {
  name: string;
  start_line: number;
  end_line: number;
  coverage: number | 'ignored';
}

export interface GroupData extends StatGroup {
  files?: string[];
}

declare global {
  interface Window {
    SIMPLECOV_DATA: CoverageData;
  }
}
