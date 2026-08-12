SimpleCov [![Gem Version](https://badge.fury.io/rb/simplecov.svg)](https://badge.fury.io/rb/simplecov) [![Build Status](https://github.com/simplecov-ruby/simplecov/actions/workflows/stable.yml/badge.svg?branch=main)][ci] [![Lint](https://github.com/simplecov-ruby/simplecov/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/simplecov-ruby/simplecov/actions/workflows/lint.yml) [![Typecheck](https://github.com/simplecov-ruby/simplecov/actions/workflows/typecheck.yml/badge.svg?branch=main)](https://github.com/simplecov-ruby/simplecov/actions/workflows/typecheck.yml) [![Maintainability](https://api.codeclimate.com/v1/badges/c071d197d61953a7e482/maintainability)](https://codeclimate.com/github/simplecov-ruby/simplecov/maintainability)
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
project root when several test suites share it. Some of the most common
settings:

```ruby
SimpleCov.start do
  enable_coverage :branch            # track branches as well as lines
  cover "{app,lib}/**/*.rb"          # report on these files, even if never loaded
  skip "app/legacy"                  # ...but leave these out
  group "Models", "app/models"       # organize the report into groups

  coverage :line do
    minimum      90                  # fail the suite below 90% line coverage
    maximum_drop 1                   # ...or when coverage drops more than 1%
  end
end
```

Every option is documented in [docs/Configuration.md](docs/Configuration.md),
including criteria, filters, groups, profiles, and thresholds.

## Copyright

Copyright (c) 2010-2026 Erik Berlin, Benjamin Fleischer, Akira Matsuda, Christoph Olszowka, Tobias Pfeiffer, David Rodríguez, and Xavier Shay. See LICENSE for details.
