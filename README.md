SimpleCov [![Gem Version](https://badge.fury.io/rb/simplecov.svg)](https://badge.fury.io/rb/simplecov) [![Build Status](https://github.com/simplecov-ruby/simplecov/actions/workflows/stable.yml/badge.svg?branch=main)][ci] [![Lint](https://github.com/simplecov-ruby/simplecov/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/simplecov-ruby/simplecov/actions/workflows/lint.yml) [![Typecheck](https://github.com/simplecov-ruby/simplecov/actions/workflows/typecheck.yml/badge.svg?branch=main)](https://github.com/simplecov-ruby/simplecov/actions/workflows/typecheck.yml) [![Mutation](https://github.com/simplecov-ruby/simplecov/actions/workflows/mutation.yml/badge.svg?branch=main)](https://github.com/simplecov-ruby/simplecov/actions/workflows/mutation.yml) [![Maintainability](https://api.codeclimate.com/v1/badges/c071d197d61953a7e482/maintainability)](https://codeclimate.com/github/simplecov-ruby/simplecov/maintainability)
=========

**Code coverage for Ruby**

[ci]: https://github.com/simplecov-ruby/simplecov/actions?query=workflow%3Astable

SimpleCov is a code coverage analysis tool for Ruby. It uses [Ruby's built-in
Coverage][Coverage] library to gather coverage data, but makes processing the
results much easier by providing a clean API to filter, group, merge, format,
and display them. You can get a full coverage setup running in a couple of
lines of code.

[Coverage]: https://docs.ruby-lang.org/en/master/Coverage.html

SimpleCov tracks covered Ruby code.

In most cases you'll want overall coverage results spanning all of your tests
(unit, integration, etc.). SimpleCov handles this automatically by caching and
merging results as it generates reports, so a report reflects coverage across
your whole test suite and gives you a truer picture of your blank spots.

SimpleCov bundles two formatters: the default HTML formatter (which renders the
browsable report) and a JSON formatter. Both were once separate gems
(`simplecov-html` and `simplecov_json_formatter`) but are now built into
SimpleCov and configured automatically when you launch it. A wide variety of
[alternate formatters](docs/Alternate_Formatters.md) are distributed as gems.

## Getting started

1. Add SimpleCov to your `Gemfile` and `bundle install`:

    ```ruby
    gem 'simplecov', require: false, group: :test
    ```

2. Load and launch SimpleCov **at the very top** of your test helper, whether
   that's `test/test_helper.rb`, `spec/spec_helper.rb`, `rails_helper.rb`, or
   Cucumber's `features/support/env.rb`. SimpleCov doesn't care which framework
   you run. It watches what code executes and reports on it, so the same two
   lines work everywhere:

    ```ruby
    require 'simplecov'
    SimpleCov.start

    # Previous content of test helper now starts here
    ```

   > **Important:** `SimpleCov.start` **must** run **before any of your
   > application code is required**. Otherwise SimpleCov (and the underlying
   > Coverage library) can't track those files. This bites hardest with tools
   > that keep your app loaded between runs, like Spring. See the
   > [Spring section](docs/Troubleshooting.md#using-spring-with-simplecov).

   SimpleCov must run in the process you want to analyze. When you test a
   server process (e.g. a JSON API) from a separate test process (e.g. via
   Selenium) and want to see all the code the `rails server` executes, not just
   the code in your test files, require SimpleCov in the server process. For
   Rails, add this near the top of `bin/rails`, below the shebang and after
   `config/boot` is required:

    ```ruby
    if ENV['RAILS_ENV'] == 'test'
      require 'simplecov'
      SimpleCov.start 'rails'
    end
    ```

3. Run your full test suite to see your application's coverage.

4. Open the HTML report in your default browser:

    ```sh
    simplecov open
    ```

   (The bundled `simplecov` CLI picks the right opener for your platform:
   `open` on macOS, `xdg-open` on Linux/BSD, `start` on Windows. Pass
   `--report PATH` to open a non-default location. See the
   [command-line interface](docs/CLI.md) for the full set of subcommands.)

5. Optionally, keep coverage results out of Git:

    ```sh
    echo coverage >> .gitignore
    ```

For Rails applications, SimpleCov ships a built-in `rails`
[profile](docs/Configuration.md#profiles) that sets up groups for your
Controllers, Models, Helpers, and Libraries:

```ruby
require 'simplecov'
SimpleCov.start 'rails'
```

## Example output

#### Coverage results report

![SimpleCov coverage report](https://github.com/user-attachments/assets/19cbbf09-e42e-49c2-9adc-2427f321cb7f)

#### Source file coverage details view

![SimpleCov source file detail view](https://github.com/user-attachments/assets/c168597d-a82c-453a-825b-3fb229979c5e)

## Configuration at a glance

Configuration goes in your start block, or in a `.simplecov` file at the
project root when several test suites share it. The API is built around a
small set of consistent verbs: formatters are picked by name, thresholds
live in a per-criterion `coverage` block where scope is a uniform `per:`
argument, and misses can be capped as absolute counts rather than ratios:

```ruby
SimpleCov.start do
  enable_coverage :branch            # track branches as well as lines
  cover "{app,lib}/**/*.rb"          # report on these files, even if never loaded
  skip "app/legacy"                  # ...but leave these out
  group "Models", "app/models"       # organize the report into groups

  coverage :line do
    minimum      90                  # fail the suite below 90% line coverage
    maximum_drop 1                   # ...or when coverage drops more than 1%
    maximum_missed 5, per: :file     # no file may carry more than 5 uncovered lines
  end

  coverage :branch, minimum: 80, ignore: :implicit_else
end
```

Everything you're using today keeps working. Legacy spellings warn and name
their replacement, and once you've migrated, `deprecations :raise` turns any
old spelling that creeps back in into an error. The
[migration map](docs/Configuration.md#migrating-from-the-legacy-configuration-api)
has the full before and after, and every option is documented in
[docs/Configuration.md](docs/Configuration.md), including criteria, filters,
groups, profiles, and thresholds.

## Tracking which test covers each line

Coverage normally tells you whether a line ran, not what ran it. `track_tests`
records the other half of the story:

```ruby
SimpleCov.start do
  track_tests
end
```

RSpec examples and Minitest tests are wrapped automatically. In the HTML
report, covered lines that no test executed (they only ran at load time, or in
suite setup) drain to a distinct tint, so coverage that merely *loads* code
stops passing for coverage that *tests* it, and clicking a line's badge lists
the tests that cover it. The same recording answers from the terminal:

```sh
$ simplecov tests lib/simplecov/result.rb:42
spec/result_spec.rb:42
```

The output is one test id per line and nothing else, so it pipes straight into
a runner. `simplecov tests --redundant` inverts the question, listing the
tests whose covered lines other tests also cover, which is where a
[test-pruning session](docs/Redundant_Tests.md) starts. Recording has a real
cost, which is why it's opt-in and comes with levers to control it. See
[the configuration docs](docs/Configuration.md#tracking-which-test-covers-each-line).

## Finding dead code in production

SimpleCov can also measure production code usage, the surest way to find
dead code. The old trick was to plant a log line in a suspect method and
watch production for a while. Oneshot coverage runs that experiment for
every line at once: a line reports its first execution and nothing after,
so a live process records what real traffic uses with the least possible
impact on performance. `simplecov dead-code` then crosses the recording
with the test report and turns it into insight you can act on. Code
neither tests nor traffic touch is safe to delete, and code production
runs but tests skip is the most valuable test you haven't written. The
HTML report and `coverage.json` include the same production data. See
[docs/Production.md](docs/Production.md) for more details on why and how
to set it up.

## Coverage of just your change

An overall number moves slowly on a mature codebase, but "is the code in this
change tested?" has a crisp answer the day you ask it. `simplecov patch` reads
the git diff against a base ref and scores only the lines you touched:

```sh
$ simplecov patch --base main --minimum 100
   88.00% (22/25) lines  lib/simplecov/cli/patch.rb  missing 41-43
  100.00% (4/4) lines    lib/simplecov/result.rb
  Patch coverage:  89.66% (26/29) lines
```

`--minimum` turns it into a gate, so a project that can't lift its overall
number in one pull request can still require that everything it adds is
covered. The flip side is `simplecov affected`, which uses a `track_tests`
recording to select the tests that touch your changed code and hand them to
the runner, falling back (loudly) to the full suite whenever the map can't be
trusted:

```sh
$ simplecov affected --base main --run bundle exec rspec
```

Both commands are documented in [the CLI docs](docs/CLI.md).

## Covering views

View templates execute real logic, and now they can be part of the report.
`cover_views` brings ERB, Haml, and Slim templates in, measured through eval
coverage:

```ruby
SimpleCov.start 'rails' do
  cover_views
end
```

Templates are ordinary files in the report, highlighted in their own language
and grouped under Views by the `rails` profile, and a template no test renders
shows up at 0% instead of being quietly missing. Expect your overall number to
drop the first time you turn this on. That's the point. See
[view coverage](docs/Configuration.md#view-coverage).

## Per-file ratchets and coverage history

On a legacy codebase, one per-file minimum does nothing useful: set it to what
the worst file scores and every other file is allowed to sink to that level.
`simplecov ratchet` writes a checked-in baseline instead, giving each file its
own floor at the coverage it has already reached:

```sh
$ simplecov ratchet
simplecov ratchet: wrote .simplecov_baseline.yml (3 tightened, 1 pruned, 148 unchanged)
```

Floors only ever tighten, so touching a legacy file drags its coverage upward
and it can never slide back. Think `.rubocop_todo.yml`, applied to coverage.
To ratchet automatically at the end of every run, add the baseline formatter
with `formats :html, :baseline`.

Alongside the floors, every successful run now appends to
`coverage/.history.json`, so you have a recorded trend rather than just the
last number. `simplecov history` draws it as sparklines in the terminal, and
`drop_baseline :median` judges coverage drops against the recorded median
instead of whatever the previous run happened to score. See
[the baseline](docs/Configuration.md#per-file-baseline-ratchet) and
[run history](docs/Configuration.md#run-history) docs.

## More from the command line

The `simplecov` CLI has grown from a report opener into a toolbelt. A few
favorites:

```sh
$ simplecov watch bundle exec rspec   # re-run on save, live-reload the served report
$ simplecov show lib/foo.rb           # annotated source in the terminal
$ simplecov status                    # is this report fresh, and for which commit?
$ simplecov uncovered --missing       # worst files, with the exact line ranges to test
$ simplecov badge --output badge.svg  # a shields.io-style SVG, no badge service needed
```

`watch` deserves the highlight: with a `track_tests` recording in the report,
a save re-runs only the tests that touch the files you changed, which turns
the report into something you keep open while writing the test. There is also
shell tab completion (`simplecov completions fish|bash|zsh`), a man page, and
a real `--help` on every command. The full tour is in
[docs/CLI.md](docs/CLI.md).
