// Mutation testing for the viewer (https://stryker-mutator.io), the frontend
// counterpart of the Ruby side's `rake mutant`. Run with `bun run mutate`.
//
// The tests run under `bun test`, which Stryker has no runner plugin for, so
// the command runner runs the whole suite per mutant. That is affordable here:
// the suite finishes in under two seconds.
/** @type {import('@stryker-mutator/core').PartialStrykerOptions} */
export default {
  testRunner: 'command',
  commandRunner: {command: 'bun test --config=bunfig.stryker.toml'},
  mutate: ['src/**/*.ts'],
  // The command runner cannot report per-test coverage, so every mutant runs
  // the full suite.
  coverageAnalysis: 'off',
  // Stryker rewrites a sandboxed tsconfig through TypeScript's compiler API,
  // which the Go-based TypeScript 7 no longer ships. `bun test` strips types
  // without reading tsconfig, so the sandbox simply goes without one.
  ignorePatterns: ['tsconfig.json'],
  reporters: ['progress', 'clear-text', 'html'],
  htmlReporter: {fileName: 'reports/mutation/index.html'},
  tempDirName: '.stryker-tmp',
  cleanTempDir: true,
  timeoutMS: 15000,
  // Every mutant is either killed or carries a `Stryker disable` directive
  // naming why it is equivalent, so one survivor fails the run.
  thresholds: {high: 100, low: 90, break: 100},
};
