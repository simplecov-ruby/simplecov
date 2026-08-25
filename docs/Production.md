# Coverage in production

Measure what real traffic executes, and cross it with the test report to find dead code.

*Part of the [SimpleCov](../README.md) documentation.*

## Coverage in production

Oneshot lines coverage is cheap enough to leave running in production: each line reports its first execution and
nothing after, so the steady-state overhead is near zero. `SimpleCov::Production` turns that into a supported mode: a
live process measures which of its lines ever run, drains the measurements to a shared store on an interval, and
`simplecov dead-code` later crosses that store with the test report. The union of a test suite and real traffic
answers a question neither answers alone, and coverage over a long enough window is far better evidence for deleting
Ruby than any static analysis of it.

Nothing here runs unless explicitly started, and `require "simplecov/production"` loads none of the reporting
machinery, no formatters, and no at-exit report. A process that starts production coverage gets a measurement tap and
a background flush thread, nothing else.

### Starting it

```ruby
# config/initializers/coverage.rb, a boot hook, or wherever your app initializes
require "simplecov/production"

SimpleCov::Production.start(
  root: Rails.root.to_s,
  sink: SimpleCov::Production::FileSink.new(path: "/var/data/coverage/production.json"),
  flush_interval: 60,            # seconds between drains (default 60)
  sample_rate: 1.0,              # fraction of intervals measured (default 1.0; below 1 needs Ruby 3.2+)
  max_buffered_lines: 1_000_000  # ceiling on lines held across failed flushes (default one million)
)
```

`start` returns true when measurement began and false, with a warning naming why, when it safely declined: production
coverage is already running, another Coverage owner exists (a test suite must always win), or the runtime has no
oneshot lines support. Configuration mistakes raise instead, because a typo'd interval should fail deployment rather
than quietly measure wrong.

In a forking server, start from the worker-boot hook. The flush thread does not survive a fork, and `start` in the
child picks the inherited measurement back up:

```ruby
# puma.rb
on_worker_boot { SimpleCov::Production.start(root: ..., sink: ...) }
```

`SimpleCov::Production.stop` flushes the final delta and halts the instrumentation; an at-exit hook does the same for
processes that die without calling it. `SimpleCov::Production.flush` forces a drain, for deploy hooks or signal
handlers.

### Sampling and the buffer

`sample_rate` is a duty cycle: at 0.25, roughly one flush interval in four is measured and the rest are suspended,
capping the steady-state overhead while every line still gets its chance over time. The first interval after `start`
always measures. Rates below 1.0 use `Coverage.suspend` / `Coverage.resume` and therefore need Ruby 3.2 or later.

When the sink is unreachable, drained lines are buffered in memory and retried on the next interval, bounded by
`max_buffered_lines`. Past the ceiling the buffer is dropped with a warning. Oneshot's clear-on-drain semantics make
the drop heal itself for code that is still running (a hit line re-reports after each drain), so what a drop actually
loses is code that ran only during the outage.

### Sinks

Writing into a repository's coverage directory is not a production storage strategy, so storage is pluggable. A sink
is any object with one method:

```ruby
def store(coverage) # {"app/models/user.rb" => [1, 5, 12], ...}
```

It receives root-relative paths mapped to sorted line numbers (the delta since the last successful flush), must
union-merge into shared storage (many processes each hold only a slice), must tolerate receiving the same lines twice,
and signals failure by raising, which makes the runtime keep the delta and retry. Redis, S3, or a metrics pipeline
implement this one method and live outside the gem.

The bundled `SimpleCov::Production::FileSink` merges into a single JSON file under an exclusive lock, which is enough
for any number of processes sharing a host or a mounted volume:

```json
{"simplecov_production": {
  "format_version": 1,
  "started_at": "2026-08-01T05:00:00Z", "updated_at": "2026-08-25T11:00:00Z",
  "coverage": {"app/models/user.rb": [1, 5, 12]}}}
```

A remote sink that wants `simplecov dead-code` to read its data only has to download it into this shape.

### Finding dead code

With a production file accumulated over a real window and a test report (`coverage.json`) from your suite:

```sh
$ simplecov dead-code --production /var/data/coverage/production.json
Production coverage: /var/data/coverage/production.json (window 2026-08-01T05:00:00Z to 2026-08-25T11:00:00Z)

Dead code (not run in production, not covered by tests):
  app/models/legacy_import.rb:4-30 (entire file)
Possibly dead (not run in production, covered only by tests):
  app/services/rollback.rb:12-19

27 dead lines, 8 possibly dead lines
```

Per line, production and tests cross into four cells: run in both is normal; run in production but untested is the
highest-value place to add a test (`--untested-in-production` prints those); tested but never run in production is
possibly dead, a deletion candidate whose only defender is its own spec; run by neither is dead. The default view
prints the two deletion-candidate rows, a file whose every relevant line skipped production is marked `(entire
file)`, and `--json` emits all three categories with the window, for tooling.

The header names the window because the window is the evidence: a day of traffic misses monthly jobs, and a month
misses yearly ones. Read "dead" as "dead over this window, as far as this traffic saw".

See the [command-line interface](CLI.md#dead-code--cross-production-coverage-with-the-test-report) for the full
option listing.
