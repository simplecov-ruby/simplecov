// Shared types for the coverage report data (the JSON shape emitted by the
// Ruby JSONFormatter and assigned to `window.SIMPLECOV_DATA`).

export interface CoverageData {
  meta: {
    simplecov_version: string;
    command_name: string;
    // The distinct run names behind the report, one per merged run.
    // Optional: documents from before the key existed carry only the
    // joined command_name.
    command_names?: string[];
    project_name: string;
    timestamp: string;
    root: string;
    primary_coverage?: string;
    line_coverage: boolean;
    branch_coverage: boolean;
    method_coverage: boolean;
  };
  total: StatGroup;
  coverage: Record<string, FileCoverage>;
  // Recorded context ids (each one a test under `track_tests`), present
  // only when the run recorded them. Per-file bitmaps index into this.
  contexts?: string[];
  // The run history (coverage/.history.json entries, oldest first, the
  // reported run appended last), present only when past runs are
  // recorded. Powers the trend sparklines.
  history?: HistoryEntry[];
  groups: Record<string, GroupData>;
}

export interface HistoryEntry {
  created_at: string;
  branch?: string | null;
  commit?: string | null;
  // Percents keyed by criterion ("line" / "branch" / "method").
  totals?: Record<string, number>;
  groups?: Record<string, Record<string, number>>;
  // Primary-criterion percent per project-relative path.
  files?: Record<string, number>;
}

export type CoverageType = 'line' | 'branch' | 'method';

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
  // Hex bitmaps of covered lines keyed by context index; absent when no
  // recorded context touched the file (see src/contexts.ts).
  contexts?: Record<string, string>;
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
