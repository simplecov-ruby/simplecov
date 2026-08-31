# Merging results and parallel tests

How SimpleCov merges results across suites, processes, workers, and machines.

*Part of the [SimpleCov](../README.md) documentation.*

## Merging results and parallel tests

You normally want coverage analyzed across ALL of your test suites at once. SimpleCov automatically caches results in
`(coverage_path)/.resultset.json` and merges them with subsequent runs — or overrides them, depending on whether it
considers a subsequent run a different test suite or the same one. To make that distinction, SimpleCov uses the concept
of **test suite names**.

### Test suite names

SimpleCov guesses the running suite's name from the shell command that started the tests. This works fine for Test::Unit,
RSpec, and Cucumber; if it fails, it falls back to the invoking shell command as the command name.

For a non-standard setup, give SimpleCov a cue with `SimpleCov.command_name` in one test file per suite (you only need
it once per suite — even with 200 unit test files, setting it in one is enough):

```ruby
# test/unit/some_test.rb
SimpleCov.command_name 'test:units'

# test/functionals/some_controller_test.rb
SimpleCov.command_name "test:functionals"

# test/integration/some_integration_test.rb
SimpleCov.command_name "test:integration"

# features/support/env.rb
SimpleCov.command_name "features"
```

**If multiple suites resolve to the same `command_name`, their results clobber each other instead of merging.**
SimpleCov detects unique names for the most common setups, but if you have more than one suite that doesn't follow a
common pattern, ensure each gets a unique `command_name`.

When running tests in parallel, each process can clobber the others' results. With the default `command_name`,
SimpleCov detects and avoids collisions based on `ENV['PARALLEL_TEST_GROUPS']` and `ENV['TEST_ENV_NUMBER']`. If your
runner sets neither, *you must* set a `command_name` that's unique per process (e.g. `command_name "Unit Tests PID #{$$}"`).
With parallel_tests specifically, incorporate `TEST_ENV_NUMBER` into the name yourself so results merge correctly:

```ruby
# spec/spec_helper.rb
SimpleCov.command_name "features" + (ENV['TEST_ENV_NUMBER'] || '')
```

The HTML report prints the test suites it used in its footer.

### Merging within one execution environment

Results are automatically merged with previous runs in the same execution environment when the report is generated, so
once coverage is set up for Cucumber and your unit / functional / integration tests, all of those suites feed into one
report.

Cached coverage data eventually goes stale, so result sets older than `SimpleCov.merge_timeout` are dropped from the
merge. The default is 600 seconds (10 minutes); raise or lower it with `SimpleCov.merge_timeout 3600` (1 hour), or
`merge_timeout 3600` inside a configure/start block. Deactivate automatic merging entirely with `SimpleCov.merging false`.

In a parallel run, every worker stores only its own result. The adapter-selected final process then waits for the other
workers to finish, reads the resultset, and builds the merged report. It gives up after
`SimpleCov.parallel_wait_timeout` seconds (default 60) and reports whatever has arrived, skipping the minimum / maximum
coverage checks against that partial total. If one worker runs much heavier test files and routinely finishes a minute
or more after the others, raise it with `SimpleCov.parallel_wait_timeout 180` so its coverage is included.

SimpleCov tags cached entries with a per-run identity so results left by an earlier invocation cannot satisfy that
wait. The built-in adapters infer a shared identity for local workers. Distributed or custom runners whose workers do
not share a launcher process should set the same `SIMPLECOV_RUN_ID` environment variable in every worker.

### Merge finalization ownership

`SimpleCov.merging true` stores each process' resultset so it can be merged with other suites or workers. By default,
SimpleCov also owns **finalizing** that merge: waiting for sibling workers, building the merged result, formatting the
report, enforcing minimum / maximum coverage, and writing `.last_run.json`.

Some parallel runners intentionally write each worker's resultset to a separate coverage directory and then run an
explicit cleanup step with `SimpleCov.collate`. In that setup, workers should still store their resultsets, but the
cleanup task owns finalization:

```ruby
# spec/spec_helper.rb
SimpleCov.start do
  if ENV["TEST_ENV_NUMBER"]
    merging true
    coverage_dir "coverage/turbo_tests/#{ENV["TEST_ENV_NUMBER"]}"
    command_name "rspec-#{ENV["TEST_ENV_NUMBER"]}"
    finalize_merge false
  end
end
```

```ruby
# Rakefile
task "coverage:collate" do
  require "simplecov"

  SimpleCov.collate Dir["coverage/turbo_tests/*/.resultset.json"] do
    coverage(:line) { minimum 100 }
    coverage(:branch) { minimum 100 }
  end
end
```

When `finalize_merge false`, the worker writes its `.resultset.json` and exits without waiting for siblings, formatting,
checking thresholds, or writing `.last_run.json`. The `SimpleCov.collate` process is the finalizer and performs those
steps for the merged result.

For compatibility, SimpleCov infers `finalize_merge false` and prints a configuration warning only when all of these are
true: a recognized parallel adapter is active, more than one worker is expected, merging is enabled, the coverage
destination was explicitly changed from the default, and the process has parallel-worker environment variables. Set
`SimpleCov.finalize_merge false` to keep external collation ownership without the warning, or
`SimpleCov.finalize_merge true` if the selected worker should own the built-in wait / merge / report flow even with a
custom coverage destination.

### Merging across execution environments

If your tests run in parallel across multiple build machines, download each run's `.resultset.json` and merge them into
a single result set with `SimpleCov.collate`:

```ruby
# lib/tasks/coverage_report.rake
namespace :coverage do
  desc "Collates all result sets generated by the different test runners"
  task :report do
    require 'simplecov'

    SimpleCov.collate Dir["simplecov-resultset-*/.resultset.json"]
  end
end
```

`SimpleCov.collate` also takes an optional profile and an optional configuration block, just like `SimpleCov.start` or
`SimpleCov.configure`. This means you can configure a separate formatter for the collated output — for instance, use the
plain `SimpleCov::Formatter::SimpleFormatter` in each worker's `SimpleCov.start` and reserve heavier formatters for the
final `SimpleCov.collate` run:

```ruby
# spec/spec_helper.rb
require 'simplecov'

SimpleCov.start 'rails' do
  # Disambiguates individual test runs
  command_name "Job #{ENV["TEST_ENV_NUMBER"]}" if ENV["TEST_ENV_NUMBER"]

  if ENV['CI']
    formatter SimpleCov::Formatter::SimpleFormatter
  else
    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::SimpleFormatter,
      SimpleCov::Formatter::HTMLFormatter
    ])
  end

  cover "{app,lib}/**/*.rb"
end
```

```ruby
# lib/tasks/coverage_report.rake
namespace :coverage do
  task :report do
    require 'simplecov'

    SimpleCov.collate Dir["simplecov-resultset-*/.resultset.json"], 'rails' do
      formatter SimpleCov::Formatter::MultiFormatter.new([
        SimpleCov::Formatter::SimpleFormatter,
        SimpleCov::Formatter::HTMLFormatter
      ])
    end
  end
end
```

#### Fanning the merge out across processes

Collating a handful of resultsets is quick. Collating a few hundred is not: the collating process reads, parses and
folds every one of them in sequence, and on a large CI matrix that fold is where nearly all the wall clock goes.

Pass `processes:` to spread that fold across forked worker processes:

```ruby
# lib/tasks/coverage_report.rake
namespace :coverage do
  desc "Collates all result sets generated by the different test runners"
  task :report do
    require 'simplecov'

    SimpleCov.collate Dir["simplecov-resultset-*/.resultset.json"], processes: 8
  end
end
```

The report is identical to the one a single-process collate produces for the same inputs, not merely equivalent: each
worker folds a contiguous slice of the file list and the collating process folds the slices back in order, so the
resultsets are visited in the same order they would be otherwise.

`processes` defaults to the `SIMPLECOV_CONCURRENCY` environment variable, or 1 when that is unset — and 1 never forks,
so existing `collate` calls behave exactly as before. Setting it in the environment lets one rake task serve runners of
different sizes without editing the task:

```sh
SIMPLECOV_CONCURRENCY=8 bundle exec rake coverage:report
```

An explicit `processes:` argument wins over the environment variable. The count is deliberately not clamped to your core
count, nor gated on some minimum number of resultsets: how many processes a collate job can afford is something only you
know. Asking for more processes than there are result files simply gives one file per process, and anything below 1 is
taken as 1, so a count computed from arithmetic that can reach zero needs no guarding.

It falls back to merging in the collating process — same report, no error — when the runtime cannot fork (JRuby,
Windows), when there is only one resultset to fold, or when a worker dies.

Merging 160 resultsets covering 1,836 files on a 14-core machine (`benchmarks/collate.rb`, so reproduce it on your own
hardware before budgeting for it):

| `processes:` | merge phase |
| ------------ | ----------- |
| 1 (default)  | 4.53s       |
| 4            | 1.70s       |
| 8            | 1.35s       |

Memory scales with the worker count rather than the resultset count: each worker folds its slice one file at a time, so
it holds one resultset plus its own running total, and the collating process holds one folded total per worker.

### Forked subprocesses

`SimpleCov.merge_subprocesses true` lets SimpleCov observe subprocesses started with `Process.fork`. It wraps Ruby's
`Process.fork` so SimpleCov can see into the child, appending `" (subprocess #{pid})"` to the `command_name`, with
results that merge back together. Configure the child with `.at_fork`:

```ruby
SimpleCov.merge_subprocesses true
SimpleCov.at_fork do |pid|
  # This needs a unique name so it won't be overwritten
  SimpleCov.command_name "#{SimpleCov.command_name} (subprocess: #{pid})"
  # be quiet, the parent process will be in charge of output and checking coverage totals
  SimpleCov.print_errors false
  SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter
  SimpleCov.minimum_coverage 0
  # start
  SimpleCov.start
end
```

SimpleCov must already be started before `Process.fork` is called.

> [!NOTE]
> The bundled `rails` profile turns this on automatically, so `ActiveSupport::TestCase.parallelize(workers: ...)`
> worker forks contribute to the merged report instead of being silently dropped.

#### Spawned subprocesses

You can also cover a Ruby script you launch with `PTY.spawn`, `Open3.popen`, `Process.spawn`, and the like. Add a
`.simplecov_spawn.rb` file to your project root:

```ruby
# .simplecov_spawn.rb
require 'simplecov' # this will also pick up whatever config is in .simplecov,
                    # so ensure it just contains configuration and doesn't call SimpleCov.start.
SimpleCov.command_name 'spawn' # As this isn't for a test runner directly, the script has no pre-defined base command_name
SimpleCov.at_fork.call(Process.pid) # Use the per-process setup described above
SimpleCov.start # only now can we start
```

Then, instead of spawning your script directly:

```ruby
PTY.spawn('my_script.rb') do # ...
```

use `ruby -r` to require the spawn file first:

```ruby
PTY.spawn('ruby -r./.simplecov_spawn my_script.rb') do # ...
```

### Parallel-test-runner adapters

SimpleCov coordinates with parallel test runners through a small pluggable adapter interface
(`SimpleCov::ParallelAdapters`). Two adapters ship out of the box:

- **`ParallelTestsAdapter`** — wraps the [grosser/parallel_tests](https://github.com/grosser/parallel_tests) gem and
  uses its `ParallelTests.first_process?` / `ParallelTests.wait_for_other_processes_to_finish` APIs for precise worker
  coordination. Activates only when the native `parallel_tests` pid-file contract is present.
- **`GenericAdapter`** — catch-all for any runner that follows the `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` env-var
  convention but doesn't ship a Ruby API (parallel_rspec, [rspec-conductor](https://github.com/markiz/rspec-conductor)
  1.0.7 or later, knapsack-style splitters, custom CI sharding scripts). Activates when `TEST_ENV_NUMBER` is set and no
  more-specific adapter is.

Adapters are tried in registration order; the first whose `active?` returns `true` is chosen. With both built-ins, this
means parallel_tests users get the precise gem-based path and parallel_rspec (or any env-var-only runner) gets the
polling-based fallback without any configuration change. See [#1065](https://github.com/simplecov-ruby/simplecov/issues/1065).

#### Registering a custom adapter

If you use a parallel runner with different env vars or its own synchronization API, define a class that inherits from
`SimpleCov::ParallelAdapters::Base` and register it:

```ruby
# In your spec_helper.rb / test_helper.rb (before SimpleCov.start)
class MyRunnerAdapter < SimpleCov::ParallelAdapters::Base
  def self.active?
    !ENV["MY_RUNNER_PID"].nil?
  end

  def self.first_worker?
    ENV["MY_RUNNER_PID"].to_i == 1
  end

  def self.wait_for_siblings
    MyRunner.barrier!   # if your runner provides a sync primitive
  end

  def self.expected_worker_count
    ENV["MY_RUNNER_WORKERS"].to_i
  end
end

SimpleCov::ParallelAdapters.register MyRunnerAdapter
```

Custom adapters are inserted at the front of the selection chain, so they take precedence over the built-ins. `Base`
provides safe no-op defaults for any method you don't override (single-process semantics: `active?` returns `false`,
`first_worker?` returns `true`, etc.).


