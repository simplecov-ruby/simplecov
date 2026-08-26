# Command-line interface

The bundled `simplecov` executable and its subcommands.

*Part of the [SimpleCov](../README.md) documentation.*

## Command-line interface

The bundled `simplecov` CLI provides a set of subcommands. The read-only reporting commands consume the JSONFormatter's
`coverage.json` output, so you don't need to re-run your suite — any prior run that emitted JSON suffices. Paths default
to `SimpleCov.coverage_dir` from your project's `.simplecov` when one is present.

| Command            | Description                                                         |
|--------------------|---------------------------------------------------------------------|
| `run <command…>`   | Execute `<command>` with SimpleCov pre-loaded (no `test_helper` hook needed) |
| `coverage <path>`  | Print coverage stats for a single file                              |
| `show <path>`      | Print the file's source annotated with hit counts and misses        |
| `report`           | Print the overall summary and per-group totals                      |
| `status`           | Report freshness: age, commit distance, recorded tests              |
| `history`          | Print the recorded coverage trend, a sparkline per criterion        |
| `badge`            | Render the coverage percent as an SVG badge                         |
| `uncovered`        | List the lowest-coverage files                                      |
| `tests [<path>[:<line>]]` | List recorded tests for a file or line (needs `track_tests`) |
| `affected`         | List test files touching code changed since a git ref (needs `track_tests`) |
| `merge <files…>`   | Merge multiple `.resultset.json` files                              |
| `diff <baseline>`  | Show per-file coverage delta vs a baseline                          |
| `patch`            | Show coverage of only the lines a change touched                    |
| `ratchet`          | Rewrite the per-file coverage baseline, only ever tightening        |
| `dead-code`        | Cross production coverage with the report to find dead code         |
| `open`             | Open the HTML report in the default browser                         |
| `serve`            | Serve the coverage report over HTTP                                 |
| `watch <command…>` | Re-run `<command>` on save and live-reload the served report        |
| `clean`            | Remove the coverage report directory                                |
| `completions <shell>` | Emit the completion script for fish, bash, or zsh                |

Run `simplecov help` for the full option listing, or `simplecov <command> --help` for a single command's. The gem
also ships a man page at `man/simplecov.1`, generated from the same usage document as the help text and the shell
completions (`rake man` regenerates it, and the suite fails when the committed copy is stale). RubyGems does not
install man pages onto `MANPATH`, so read it with `man $(gem contents simplecov | grep man/simplecov.1)` or let a
system package manager place it.

### `run` — run a suite with coverage

If your project has no `test_helper.rb` hook that calls `SimpleCov.start` (or you don't want to add one), `simplecov run`
execs your test command with SimpleCov pre-loaded so a report drops into `coverage/` at the end:

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

### `show` — annotated source in the terminal

The way `go tool cover` and `llvm-cov show` print it: `simplecov show <path>` answers "what is missing in this file"
without leaving the shell or forwarding a port off a CI box. Hit counts sit in the gutter (blank for blank and
comment lines), each missed line carries a caret marker under it, and branch and method misses annotate the same way
when the report measured them:

```sh
$ simplecov show lib/simplecov/cli/diff.rb
   38    1  def call(baseline)
   39    1    rows = compare(current, load(baseline))
   40    0    return EXIT_FAILURE if rows.empty?
            ^ missed
```

`--uncovered-only` collapses the answer to the ranges alone, a form that greps, fits in a commit message, and hands
a coding agent exactly the lines whose tests are missing:

```sh
$ simplecov show --uncovered-only lib/simplecov/cli/diff.rb
lib/simplecov/cli/diff.rb:40,52-58,71
```

With no path at all, `--uncovered-only` sweeps the whole project — one `path:ranges` line per file with misses — so a
single command produces the complete "everything untested" list. A bare `--json` emits the same sweep as an array of
`{path, missed}` objects.

`--json` emits the whole annotation as data for editor integrations: the path, the missed line numbers, per-line hits
for the relevant lines, and the marker labels keyed by line. It reads only the coverage data, so it answers even when
no source text is available.

Colors follow the same `NO_COLOR`, `FORCE_COLOR`, and `--no-color` rules as everywhere else. The source comes from
the report itself when it embeds one (`source_in_json`), and otherwise from disk, accepted only while the file's
line count still matches the report's, since annotating drifted source would put hit counts on the wrong lines.

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

### `status` — is the report fresh?

Every change-aware command distrusts a stale report; `simplecov status` says whether yours is, from metadata the
artifacts have carried all along:

```sh
$ simplecov status
report coverage/coverage.json
  generated 2026-08-24T09:12:33Z (18 minutes ago)
  by simplecov 1.1.1 running RSpec
  commit 4eccdbb (3 commits behind HEAD)
  line 92.50%, branch 88.00%
  tests recorded: 214 (track_tests)
resultset coverage/.resultset.json
  RSpec: 18 minutes ago
```

The commit distance comes from comparing the report's recorded commit with the current `HEAD`, so "is this report
about the code I'm looking at?" has a one-command answer. A report with no test map says what to enable, and `--json`
emits the same facts as data.

### `history` — the recorded coverage trend

Every successful run appends to `coverage/.history.json` (see the
[run history](Configuration.md#run-history)); `simplecov history` draws the trend in the terminal, a sparkline per
measured criterion with the run rows beneath:

```sh
$ simplecov history
Coverage history: coverage/.history.json (12 runs)

  line    ▄▅▆▆▇▇▇█████  97.2% → 98.5%  (+1.3)
  branch  ▂▃▃▄▄▅▅▅▆▆▆▆  88.0% → 91.25%  (+3.25)

  2026-08-14T09:12:00Z  main  4eccdbb  line 97.2%  branch 88.0%
  ...
```

`--file PATH` follows one file's trajectory instead of the totals, with the same per-criterion sparklines and gaps
where a run recorded nothing for it, and
`--json` emits the entries (or the file's trajectory) as data. Sparklines are scaled to each series' own range, so
direction stays visible even when the numbers move within a fraction of a percent; the numbers beside them carry the
absolute scale.

### `badge` — an SVG coverage badge

`simplecov badge` renders the report's percentage as a flat SVG badge in the shields.io style, with no badge service
in the loop, so a README or a CI artifact can carry the number straight from the local report:

```sh
$ simplecov badge --output coverage/badge.svg
```

Without `--output` the SVG goes to stdout. The color follows the ladder badge services use for coverage (bright green
at 90% and above, stepping down to red below 50%), `--criterion line|branch|method` picks which percentage the badge
shows, and the label names the chosen criterion ("line coverage", "branch coverage", "method coverage") unless
`--label TEXT` replaces it. The percent comes from the totals `coverage.json` already carries, so the badge always
matches what the other read-only commands report.

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
`10`); `--criterion line|branch|method` chooses which coverage to rank by (default `line`). `--missing` appends the
missed line ranges to each row (`50.00%  5/10  lib/foo.rb  missing 4-7,9`), following the chosen criterion, so the
list says not just where to add tests but which lines they're for. `--annotate github` emits `::warning` workflow
commands instead of rows, one per contiguous missed range with project-relative paths, so a plain GitHub Actions
workflow gets inline diff annotations with no upload step and no code-scanning permissions. `--json` emits the rows
as a JSON array (empty when nothing is below the threshold, with a `missing` array per row under `--missing`),
useful for piping into a CI gate.

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

### `affected` — select the tests that touch changed code

With [`track_tests`](Configuration.md#tracking-which-test-covers-each-line) enabled, `simplecov affected` turns the
recording into test selection. It diffs the working tree against the merge base of a git ref (`--base`, defaulting
to the branch origin's HEAD points at, else `main`) and HEAD, so uncommitted work counts as part of the change while commits that landed on the base after the
branch point do not, and prints the test files whose recorded tests touch the changed code, one per line. `--run`
hands them to the runner:

```sh
$ simplecov affected --base main
spec/result_spec.rb
spec/source_file_spec.rb

$ simplecov affected --base main --run bundle exec rspec
```

Everything after `--run` is the command, the selected files are appended to it, and the exit status is the
command's own.

The set intersection is the easy half. The hard half is knowing when to distrust the map, because a test map is
stale the moment something changes that no test mentions by name. Any changed file outside the tracked set falls
back to the full suite: `Gemfile.lock`, `.simplecov`, spec helpers, the runner configuration, and any changed file
the report has no data for at all. Changed or brand-new test files always run, whether the map knows them or not.
The fallback is loud, with each trigger named on stderr, and on stdout it prints nothing, which composes with
substitution (`bundle exec rspec $(simplecov affected)` runs everything when the selection cannot be trusted). With
`--run` the command runs bare, which means the full suite for the usual runners. `--json` emits
`{"full_suite": ..., "triggers": [...], "tests": [...]}` for tooling.

Like `patch`, the diff is anchored at the repository root, so a run from a subdirectory selects over the whole change
(with `--run` starting the runner at that root), and changed files resolve against the report by exact path, so a
lookalike entry elsewhere in the report can never stand in for a changed file the report does not carry.

This is built for the local inner loop. A wrong answer in CI is a green build on a broken change, so adopt it there
with your eyes open. The merge-base diff needs git 2.30 or later.

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
`git diff --unified=0 --merge-base <base>`, intersects the added and modified line numbers with the current report
(`--input`), and prints line coverage — plus branch and method coverage over the branches and methods those lines
carry, when the report measured them — over only that change, so a project that cannot move its overall number in one
pull request can still require that everything it adds is covered. The `branches` and `methods` columns and the
`branch <lines>` / `method <lines>` notes appear only for files whose touched lines actually held one.

```sh
$ simplecov patch --base main
   88.00% (22/25) lines   50.00% (1/2) branches  lib/simplecov/cli/patch.rb  missing 41-43  branch 39
  100.00% (4/4) lines  lib/simplecov/result.rb
  Patch coverage:  89.66% (26/29) lines, 50.00% (1/2) branches
```

`--base REF` selects the ref to diff against (defaulting to the branch origin's HEAD points at, else `main`; in CI
pass the pull request's target branch). The diff
runs against the merge-base of `REF` and the working tree, so uncommitted edits count too — running `simplecov patch`
before committing still scores the lines just written. `--minimum N` exits non-zero when patch coverage falls below N% — every measured criterion, line, branch,
and method alike, must clear the floor — so it gates a change alongside the overall thresholds even when they
are already satisfied:

```sh
$ simplecov patch --base origin/main --minimum 100
```

`--find-renames` follows a renamed file instead of counting the moved file as entirely new, and `--json` emits the rows
as a JSON array. Only files the report already tracks are scored — a changed file outside the configured `cover` /
`track_files` set is out of scope — and a touched line SimpleCov considers never relevant (blank or comment) stays out of
the denominator, so a comment-only change reports nothing to cover rather than a gap.

The diff is anchored at the repository root, so the command reports the same change from any subdirectory, and a
brand-new file that was never `git add`ed counts too, with every line the report knows for it scored as new. Changed
files resolve against the report by exact path, and when a changed line lies beyond what the report knows for its
file, the command warns that the report looks stale instead of silently scoring nothing. Generate the report first:
run your suite with the JSON formatter enabled, then `simplecov patch` reads `coverage/coverage.json`.

### `ratchet` — per-file floors that only tighten

`simplecov ratchet` writes `.simplecov_baseline.yml`, the checked-in per-file floor set the exit check enforces (see
[Per-file baseline](Configuration.md#per-file-baseline-ratchet)). The first run generates a floor for every file the
report carries, at the coverage it has already reached. Later runs only tighten: files that improved get their floors
raised, files that regressed keep the floors they are now below, entries for deleted files are pruned, and new files
never get an entry, so they stay answerable to the real per-file minimum instead of a grandfathered one.

```sh
$ simplecov ratchet
simplecov ratchet: wrote .simplecov_baseline.yml (3 tightened, 1 pruned, 148 unchanged)
simplecov ratchet: 2 files below their floors, entries kept unchanged
```

`--baseline PATH` names the file to rewrite (defaulting to the project's `SimpleCov.baseline_file`, read from
`.simplecov` the way the other commands read `coverage_dir`), `--input` picks the report, `--dry-run` prints without
writing, and `--json` emits the summary (tightened, pruned, and regressed paths) as data. `--init` is the deliberate
escape hatch: it regenerates the whole file from the current state, adding entries for new files and resetting floors,
regressions included.

### `dead-code` — cross production coverage with the test report

With [production coverage](Production.md) accumulated by a `SimpleCov::Production` sink, `simplecov dead-code`
crosses what real traffic ran with what the tests cover. Per line, the two cross into four cells: run in both is
normal, and the other three are worth hearing about:

```sh
$ simplecov dead-code --production /var/data/coverage/production.json
Production coverage: /var/data/coverage/production.json (window 2026-08-01T05:00:00Z to 2026-08-25T11:00:00Z)

Dead code (not run in production, not covered by tests):
  app/models/legacy_import.rb:4-30 (entire file)
Possibly dead (not run in production, covered only by tests):
  app/services/rollback.rb:12-19 (last run 2026-08-03)

27 dead lines, 8 possibly dead lines
```

The default view prints the deletion candidates: dead (run by neither) and possibly dead (kept alive only by its own
spec). `--untested-in-production` prints the remaining cell, code real users are running that no test covers, which
is the highest-value place to add a test. Rows are the same greppable `path:ranges` form `show --uncovered-only`
prints, a file whose every relevant line skipped production is marked `(entire file)`, and `--json` emits all three
categories plus the window as data. Lines the report deems irrelevant or deliberately ignored stay out of every
bucket, and a production file the report never tracked reports all its recorded lines as untested in production.

When the store carries [`last_seen` stamps](Production.md#sinks), each row dates the store's last sighting of its
file (`(last run 2026-08-03)`, with the full stamp as `last_seen` in the `--json` entries). On a dead or possibly
dead row that means other lines of the file ran then, so a recent date says the file is alive around its dead lines,
while no date at all says the window never saw the file. Rows from a store without stamps print bare.

The header names the window the production data spans because the window is the evidence: a day of traffic misses
monthly jobs. `--production` is required; `--input` picks the test report like the other read-only commands.

### `watch` — the coverage inner loop

`simplecov watch <command...>` serves the report the way `serve` does, watches the tracked files for saves, re-runs
the given command when something changes, and pushes a reload to the open report tab over server-sent events when the
report regenerates:

```sh
$ simplecov watch bundle exec rspec
watching 214 files, serving http://127.0.0.1:53422/
lib/simplecov/result.rb changed, running 3 files... 100.00% (+0.40%)
```

With a [`track_tests`](Configuration.md#tracking-which-test-covers-each-line) recording in the report, a save re-runs
only the tests that touch the changed files, by the same selection walk `simplecov affected` uses and with the same
fail-open rule: any change the map cannot be trusted for runs the full command. Without a recording, every save runs
the full command. The watched set is the report's own (its tracked files plus the recorded tests' files), polled by
mtime with no filesystem-event dependency, which also keeps writes to the coverage directory from triggering runs.

The command is the project's own test invocation and must generate the report, so a project with no
`SimpleCov.start` hook composes `simplecov watch simplecov run bundle exec rake test`. Child runs get a day-long
merge window through the `SIMPLECOV_MERGE_TIMEOUT` environment variable, so subset re-runs keep merging into a whole
report across a long session. `--port` and `--host` bind like `serve`, `--interval SECONDS` tunes the poll, and `--open` pops the report in the default browser on start
(default 0.5). The report on disk stays byte-identical to a plain run's; the reload listener joins it only on the
way out of the server.

### `serve` and `clean`

`simplecov serve` serves the coverage report over HTTP — handy on a remote box where you can't open files directly.
`--port N` binds to a specific port (default: a random open port) and `--host HOST` to a specific host (default
`127.0.0.1`). If `index.html` is missing but `coverage.json` is present, `serve` builds the self-contained HTML report
before binding. It exits with an error when neither artifact exists or the JSON cannot produce a usable report.

`simplecov clean` removes the coverage report directory. `--dry-run` prints what would be removed without deleting
anything; `-q` / `--quiet` suppresses status lines. For safety, `clean` refuses to remove the current directory, the
project root, or any of their ancestors when `coverage_dir` resolves to one of those paths.

### `completions` — tab completion for the CLI

`simplecov completions fish|bash|zsh` prints a completion script for the named shell: every subcommand with its
description, and each command's own options once a subcommand is typed. The script is generated from the same usage
document `simplecov help` prints, so a new command or option appears in completions the moment it is documented.
Install it where the shell looks:

```sh
$ simplecov completions fish > ~/.config/fish/completions/simplecov.fish
$ simplecov completions bash > ~/.local/share/bash-completion/completions/simplecov
$ simplecov completions zsh > ~/.zsh/completions/_simplecov
```

For zsh, the target directory must be in `$fpath` before `compinit` runs.


