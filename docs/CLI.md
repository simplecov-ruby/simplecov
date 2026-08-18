# Command-line interface

The bundled `simplecov` executable and its subcommands.

*Part of the [SimpleCov](../README.md) documentation.*

## Command-line interface

The bundled `simplecov` CLI provides a set of subcommands. The read-only reporting commands consume the JSONFormatter's
`coverage.json` output, so you don't need to re-run your suite — any prior run that emitted JSON suffices. Paths default
to `SimpleCov.coverage_dir` from your project's `.simplecov` when one is present.

| Command            | Description                                                         |
|--------------------|---------------------------------------------------------------------|
| `run <command…>`   | Execute `<command>` with simplecov pre-loaded (no `test_helper` hook needed) |
| `coverage <path>`  | Print coverage stats for a single file                              |
| `report`           | Print the overall summary and per-group totals                      |
| `uncovered`        | List the lowest-coverage files                                      |
| `merge <files…>`   | Merge multiple `.resultset.json` files                              |
| `diff <baseline>`  | Show per-file coverage delta vs a baseline                          |
| `patch`            | Show coverage of only the lines a change touched                    |
| `open`             | Open the HTML report in the default browser                         |
| `serve`            | Serve the coverage report over HTTP                                 |
| `clean`            | Remove the coverage report directory                                |

Run `simplecov help` for the full option listing.

### `run` — run a suite with coverage

If your project has no `test_helper.rb` hook that calls `SimpleCov.start` (or you don't want to add one), `simplecov run`
execs your test command with simplecov pre-loaded so a report drops into `coverage/` at the end:

```sh
$ simplecov run bundle exec rspec
$ simplecov run -- bundle exec rake test
$ simplecov run ruby my_test.rb
```

Internally this just sets `RUBYOPT=-rsimplecov/autostart` for the child process, so any spawned subprocess (parallel
test workers, integration test forks, etc.) also picks up the autostart shim. If your project already has a `.simplecov`
config that calls `SimpleCov.start`, the autostart shim defers to it and won't double-start Coverage.

### `coverage` — per-file lookup

For editor / TDD inner-loop integrations and tools that want one file's coverage without re-parsing the full report:

```sh
$ simplecov coverage app/models/user.rb
/abs/path/app/models/user.rb
  Line:   100.00% (12 / 12)
  Branch: 100.00% (4 / 4)
  Method: 100.00% (3 / 3)

$ simplecov coverage --json app/models/user.rb        # raw JSON entry
$ simplecov coverage --input path/to/coverage.json …  # non-default location
```

The same lookup is available in Ruby, with paths resolved relative to `SimpleCov.root` (absolute or project-relative):

```ruby
result = SimpleCov.result   # or SimpleCov::Result.from_hash(...).first
result.coverage_for("app/models/user.rb")
# => {line: <CoverageStatistics>, branch: <CoverageStatistics>, method: <CoverageStatistics>}

result.source_file_for("app/models/user.rb")
# => <SimpleCov::SourceFile>
```

### `report` — quick terminal report

For CI logs, ssh sessions, or any terminal-only workflow, `simplecov report` prints the same totals row the HTML report
renders at the top, plus per-group totals:

```sh
$ simplecov report
All Files
  Line:    99.75% (1638 / 1642)
  Branch:  98.50% (396 / 402)
  Method:  99.73% (372 / 373)
```

Pass `--input PATH` to read a non-default `coverage.json`. `--json` preserves separate `total` and `groups` namespaces,
so even a configured group named `All Files` remains distinct from the overall totals:

```json
{"total":{"lines":{"percent":99.75,"covered":1638,"total":1642}},"groups":{"Models":{"lines":{"percent":100.0,"covered":400,"total":400}}}}
```

### `uncovered` — list lowest-coverage files

`simplecov uncovered` prints the lowest-coverage files (by line coverage, worst-first) so you can find where to add
tests next without opening the HTML report:

```sh
$ simplecov uncovered
 50.00%  5/10    lib/foo.rb
 80.00%  8/10    lib/bar.rb

$ simplecov uncovered --threshold 90 --top 5
$ simplecov uncovered --criterion branch
```

`--threshold N` filters to files below N% coverage (default `100`); `--top N` caps the list at N entries (default
`10`); `--criterion line|branch|method` chooses which coverage to rank by (default `line`). `--json` emits the rows as
a JSON array (empty when nothing is below the threshold), useful for piping into a CI gate.

### `tests` — which tests cover a file or line

With [`track_tests`](Configuration.md#tracking-which-test-covers-each-line) enabled, `simplecov tests` answers the
question coverage alone cannot: not just whether a line is covered, but by which tests. Bare, it lists every recorded
test; a path narrows to the tests touching that file; `path:line` narrows to one line:

```sh
$ simplecov tests
spec/result_spec.rb:42
spec/source_file_spec.rb:12

$ simplecov tests lib/simplecov/result.rb:42
spec/result_spec.rb:42
```

Output is one test id per line, sorted, with nothing else on stdout, so the list can feed a runner directly
(`simplecov tests lib/foo.rb:42 | xargs bundle exec rspec`). An empty answer keeps stdout empty and notes it on
stderr; `--json` emits a JSON array instead. Paths match the way `simplecov coverage` matches them: project-relative,
absolute, or basename. The command reads `coverage.json`, so it needs a report generated after `track_tests` was
enabled, and it will say so when the recording is missing.

### `merge` — combine resultsets from parallel CI workers

CI matrices that produce one `.resultset.json` per worker can stitch them together with `simplecov merge` instead of
hand-rolling a Rake task in every project:

```sh
$ simplecov merge worker-*/coverage/.resultset.json --output coverage/.resultset.json
```

By default `simplecov merge` ignores `merge_timeout`; pass `--honor-timeout` to drop entries older than the configured
timeout. Pass `--dry-run` to preview the output path without writing, or `-q` / `--quiet` to suppress the success status
line for cleaner CI logs. After merging, run `simplecov report` against the combined data.

### `diff` — coverage delta vs a baseline

`simplecov diff <baseline>` reads two `coverage.json` files (current plus a baseline checked into the repo, or produced
by a previous CI run) and prints the files whose coverage moved on any enabled criterion. When branch or method coverage
is enabled, those deltas appear alongside the line delta on the same row:

```sh
$ simplecov diff coverage/baseline.json
  -20.00% lines  -10.00% branches  lib/foo.rb
  + 5.00% lines  lib/bar.rb
  +60.00% lines  lib/new.rb  (new file)
  -95.00% lines  lib/gone.rb  (removed)
```

Regressions are listed first. Pass `--fail-on-drop` to exit non-zero when any file's coverage slipped on any reported
criterion, so this composes with CI as a "coverage of this PR didn't drop" gate even when overall thresholds are still
satisfied.
`--threshold N` filters out deltas below N% in absolute value, useful when a baseline is noisy. `--json` emits the rows
as a JSON array for programmatic consumption:

```sh
$ simplecov diff --json coverage/baseline.json
[
  {"file":"lib/foo.rb","status":"changed","line_delta":-20.0,"branch_delta":-10.0,"method_delta":0.0},
  {"file":"lib/bar.rb","status":"changed","line_delta":5.0,"branch_delta":0.0,"method_delta":0.0}
]
```

Coverage keys with a leading `/` (from `coverage.json` files emitted before the `SourceFile#project_filename` change)
are normalized, so a baseline from an older SimpleCov still diffs cleanly against newer reports.

### `patch` — coverage of the lines a change touched

`simplecov patch` answers the question `diff` does not: is the code in *this change* tested? It reads
`git diff --unified=0 <base>...HEAD`, intersects the added and modified line numbers with the current report
(`--input`), and prints line coverage — plus branch coverage over the branches those lines carry, when the report
measured branches — over only that change, so a project that cannot move its overall number in one pull request can still
require that everything it adds is covered. The `branches` column and a `branch <lines>` note appear only for files whose
touched lines actually held a branch.

```sh
$ simplecov patch --base main
   88.00% (22/25) lines   50.00% (1/2) branches  lib/simplecov/cli/patch.rb  missing 41-43  branch 39
  100.00% (4/4) lines  lib/simplecov/result.rb
  Patch coverage:  89.66% (26/29) lines, 50.00% (1/2) branches
```

`--base REF` selects the ref to diff against (defaults to `main`; in CI pass the pull request's target branch, or its
merge-base). `--minimum N` exits non-zero when patch coverage falls below N% — line coverage, and branch coverage too
when the report has it, must both clear the floor — so it gates a change alongside the overall thresholds even when they
are already satisfied:

```sh
$ simplecov patch --base origin/main --minimum 100
```

`--find-renames` follows a renamed file instead of counting the moved file as entirely new, and `--json` emits the rows
as a JSON array. Only files the report already tracks are scored — a changed file outside the configured `cover` /
`track_files` set is out of scope — and a touched line SimpleCov considers never relevant (blank or comment) stays out of
the denominator, so a comment-only change reports nothing to cover rather than a gap.

Run it from the project root so the diff's `--relative` paths line up with the report's `project_filename` keys, and
generate the report first: run your suite with the JSON formatter enabled, then `simplecov patch` reads
`coverage/coverage.json`.

### `serve` and `clean`

`simplecov serve` serves the coverage report over HTTP — handy on a remote box where you can't open files directly.
`--port N` binds to a specific port (default: a random open port) and `--host HOST` to a specific host (default
`127.0.0.1`). If `index.html` is missing but `coverage.json` is present, `serve` builds the self-contained HTML report
before binding. It exits with an error when neither artifact exists or the JSON cannot produce a usable report.

`simplecov clean` removes the coverage report directory. `--dry-run` prints what would be removed without deleting
anything; `-q` / `--quiet` suppresses status lines. For safety, `clean` refuses to remove the current directory, the
project root, or any of their ancestors when `coverage_dir` resolves to one of those paths.


