SimpleCov [![Gem Version](https://badge.fury.io/rb/simplecov.svg)](https://badge.fury.io/rb/simplecov) [![Build Status](https://github.com/simplecov-ruby/simplecov/actions/workflows/stable.yml/badge.svg?branch=main)][Continuous Integration] [![Lint](https://github.com/simplecov-ruby/simplecov/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/simplecov-ruby/simplecov/actions/workflows/lint.yml) [![Typecheck](https://github.com/simplecov-ruby/simplecov/actions/workflows/typecheck.yml/badge.svg?branch=main)](https://github.com/simplecov-ruby/simplecov/actions/workflows/typecheck.yml) [![Maintainability](https://api.codeclimate.com/v1/badges/c071d197d61953a7e482/maintainability)](https://codeclimate.com/github/simplecov-ruby/simplecov/maintainability)
=========

**Code coverage for Ruby**

  * [Source Code]
  * [API documentation]
  * [Configuration]
  * [Changelog]
  * [Rubygem]
  * [Continuous Integration]

[Coverage]: https://docs.ruby-lang.org/en/master/Coverage.html "API doc for Ruby's Coverage library"
[Source Code]: https://github.com/simplecov-ruby/simplecov "Source Code @ GitHub"
[API documentation]: http://rubydoc.info/gems/simplecov/frames "RDoc API Documentation at Rubydoc.info"
[Configuration]: http://rubydoc.info/gems/simplecov/SimpleCov/Configuration "Configuration options API documentation"
[Changelog]: https://github.com/simplecov-ruby/simplecov/blob/main/CHANGELOG.md "Project Changelog"
[Rubygem]: http://rubygems.org/gems/simplecov "SimpleCov @ rubygems.org"
[Continuous Integration]: https://github.com/simplecov-ruby/simplecov/actions?query=workflow%3Astable "SimpleCov is built around the clock by github.com"

SimpleCov is a code coverage analysis tool for Ruby. It uses [Ruby's built-in Coverage][Coverage] library to gather
coverage data, but makes processing the results much easier by providing a clean API to filter, group, merge, format,
and display them — a complete coverage suite you can set up in just a couple of lines.

SimpleCov tracks covered Ruby code; gathering coverage for templating solutions like ERB, Slim, and Haml is not
supported (though see [Eval coverage](#eval-coverage) for ERB).

In most cases you'll want overall coverage results spanning all of your tests — unit tests, Cucumber features, and so
on. SimpleCov handles this automatically by caching and merging results as it generates reports, so a report reflects
coverage across your whole test suite and gives you a truer picture of your blank spots.

SimpleCov bundles two formatters that need no extra gems: the default HTML formatter (which renders the browsable
report) and a JSON formatter. Both were once separate gems (`simplecov-html` and `simplecov_json_formatter`) but are
now built into SimpleCov and configured automatically when you launch it.

## Getting started

1. Add SimpleCov to your `Gemfile` and `bundle install`:

    ```ruby
    gem 'simplecov', require: false, group: :test
    ```

2. Load and launch SimpleCov **at the very top** of your test helper — `test/test_helper.rb`, `spec/spec_helper.rb`,
   `rails_helper.rb`, Cucumber's `features/support/env.rb`, or whatever setup file your framework uses. SimpleCov
   doesn't care which framework you run in; it just watches what code executes and reports on it, so the same two lines
   work everywhere:

    ```ruby
    require 'simplecov'
    SimpleCov.start

    # Previous content of test helper now starts here
    ```

   > **Important:** `SimpleCov.start` **must** run **before any of your application code is required** — otherwise
   > SimpleCov (and the underlying Coverage library) can't track those files. This bites hardest with tools that keep
   > your app loaded between runs, like Spring; see the [Spring section](#using-spring-with-simplecov).

   SimpleCov must run in the process you want to analyze. When you test a server process (e.g. a JSON API) from a
   separate test process (e.g. via Selenium) and want to see all code the `rails server` executes — not just code in
   your test files — require SimpleCov in the server process. For Rails, add this near the top of `bin/rails`, below
   the shebang and after `config/boot` is required:

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

   (The bundled `simplecov` CLI picks the right opener for your platform — `open` on macOS, `xdg-open` on Linux/BSD,
   `start` on Windows. Pass `--report PATH` to open a non-default location. See [Command-line interface](#command-line-interface)
   for the full set of subcommands.)

5. Optionally, keep coverage results out of Git:

    ```sh
    echo coverage >> .gitignore
    ```

For Rails applications, SimpleCov ships a built-in `rails` [profile](#profiles) that sets up groups for your
Controllers, Models, Helpers, and Libraries:

```ruby
require 'simplecov'
SimpleCov.start 'rails'
```

## Example output

**Coverage results report, fully browsable locally with sorting and much more:**

![SimpleCov coverage report](https://github.com/user-attachments/assets/33275385-e0f3-482d-b63e-2a6cd4965fe0)

**Source file coverage details view:**

![SimpleCov source file detail view](https://github.com/user-attachments/assets/abcd93b4-a45d-48bb-a0e4-6129c4429193)

## Configuration

[Configuration] settings can be applied in three equivalent formats:

* Directly in your start block (the most common way):

    ```ruby
    SimpleCov.start do
      some_config_option 'foo'
    end
    ```

* As direct setters:

    ```ruby
    SimpleCov.some_config_option 'foo'
    ```

* In a `configure` block — useful when you don't want to start coverage immediately, or want to add configuration later:

    ```ruby
    SimpleCov.configure do
      some_config_option 'foo'
    end
    ```

See the [Configuration] API documentation for the full list of options.

### Using `.simplecov` for centralized config

If you merge multiple test-suite results (e.g. RSpec and Cucumber) into a single report, you'd otherwise have to repeat
your filters / groups / profile in every test helper. To avoid that, place a `.simplecov` file at your project root
with the shared configuration; each test helper then requires SimpleCov and explicitly starts it:

```ruby
# .simplecov — configuration only
SimpleCov.load_profile 'rails'
SimpleCov.skip 'lib/generators'
SimpleCov.group 'Models', 'app/models'

# spec/spec_helper.rb
require 'simplecov'
SimpleCov.start

# features/support/env.rb
require 'simplecov'
SimpleCov.start
```

This is recommended whenever you merge frameworks that rely on each other, like Cucumber and RSpec.

> [!NOTE]
> Calling `SimpleCov.start` directly from `.simplecov` is deprecated. Tracking still begins for backward
> compatibility, but a one-time deprecation warning fires; a future release will require the explicit `SimpleCov.start`
> from a test helper. Migrating prevents a long-standing bug where `.simplecov` auto-loaded in a Rakefile or Rails'
> `Bundler.require` would leave an empty parent-process report that overwrites the test subprocess's good one. See #581.

### Changing the report location

By default the report ends up in `SimpleCov.root / SimpleCov.coverage_dir`. For out-of-tree build setups
(CMake/CTest, Bazel, etc.) — where the build directory is elsewhere on the filesystem and you don't want the report
under the source root — set `SimpleCov.coverage_path` directly:

```ruby
SimpleCov.start do
  root '/source/checkout'
  coverage_path '/tmp/build/coverage'
end
```

Setting `coverage_path` explicitly pins the destination — subsequent changes to `root` or `coverage_dir` don't move
it. The directory is created if it doesn't already exist.

### Running coverage only on demand

The Ruby STDLIB Coverage library is *very* fast (on a ~10-minute Rails suite the slowdown is only a couple of seconds),
so SimpleCov's policy is to generate coverage on every run — it costs you almost nothing and you always have the latest
results. There's therefore no built-in on-demand switch, but you can add one with an `ENV` conditional:

```ruby
SimpleCov.start if ENV["COVERAGE"]
```

Then coverage runs only when you ask for it:

```sh
COVERAGE=true rake test
```

### Migrating from the legacy configuration API

The configuration API was redesigned to use a smaller set of consistent verbs. The legacy methods continue to work but
emit deprecation warnings that name their replacement; the table below is the canonical migration map.

| Legacy                              | New                              | Notes                                                                                                                  |
|-------------------------------------|----------------------------------|------------------------------------------------------------------------------------------------------------------------|
| `add_filter "lib/legacy"`           | `skip "lib/legacy"`              | Identical matcher grammar (string = path-segment substring; Regexp; block; Array). No behavior change.                 |
| `add_group "Models", "app/models"`  | `group "Models", "app/models"`   | Identical matcher grammar. No behavior change.                                                                         |
| `track_files "lib/**/*.rb"`         | `cover "lib/**/*.rb"`            | `cover` includes unloaded files (the legacy `track_files` behavior) **and** restricts the report to the matching set. To keep the old additive-only behavior, pass every directory you want reported: `cover "lib/**/*.rb", "app/**/*.rb"`. |
| `use_merging false`                 | `merging false`                  | Same value, same behavior.                                                                                             |
| `enable_for_subprocesses true`      | `merge_subprocesses true`        | Same value, same behavior.                                                                                             |
| `enable_coverage_for_eval`          | `enable_coverage :eval`          | Eval coverage now folds into the same call you use to enable `:line`/`:branch`/`:method`: `enable_coverage :branch, :eval`. |
| `print_error_status` (reader)       | `print_errors`                   | Reader only. The `print_error_status=` writer still works without a warning, but `print_errors true`/`print_errors false` is the new spelling. |
| `minimum_coverage_by_file line: 70, 'app/x.rb' => 100` | `coverage(:line) { minimum_per_file 70; minimum_per_file 100, only: 'app/x.rb' }` | The `coverage` block fixes the criterion, so per-path overrides are plain percentages with an `only:` target instead of a hash mixing Symbol / String / Regexp keys. See [Per-criterion thresholds](#per-criterion-thresholds-with-coverage). |
| `minimum_coverage_by_group 'Models' => { line: 90 }` | `coverage(:line) { minimum_per_group 90, only: 'Models' }` | Same uniform shape as `minimum_per_file`. |

Brand-new in the redesigned API (no legacy method to migrate from):

| Method                              | Purpose                                                                                                                  |
|-------------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| `cover "lib/**/*.rb"`               | Positive scope (allowlist). Multiple calls union; strings are globs. See above for the relationship with `track_files`.  |
| `no_default_skips`                  | Clear every previously-installed filter — defaults and anything earlier in the block — so subsequent `skip`s start clean.|
| `formatter false` / `formatters []` | Opt out of formatting entirely. Workers in big parallel CI runs only need their `.resultset.json` for a final `SimpleCov.collate` step; skipping the formatter saves the per-job HTML / multi-formatter overhead. See #964. |
| `parallel_tests true` / `false`     | Force on / off the auto-require of the `parallel_tests` gem. Default (unset) auto-detects from `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` and silently skips if the gem isn't installed. Set explicitly when you use those env vars for unrelated subprocess coordination. See #1018. |

Example before/after:

```ruby
# Before
SimpleCov.start do
  add_filter "/test/"
  add_filter %r{\Aconfig/}
  add_group "Models", "app/models"
  track_files "lib/**/*.rb"
  enable_coverage_for_eval
  use_merging true
  enable_for_subprocesses true
end

# After
SimpleCov.start do
  skip "/test/"
  skip %r{\Aconfig/}
  group "Models", "app/models"
  cover "lib/**/*.rb"
  enable_coverage :eval
  merging true
  merge_subprocesses true
end
```

## Coverage criteria

Line coverage is on by default. You can additionally enable branch, method, oneshot-line, and eval coverage, and choose
which criterion leads the report.

### Disabling line coverage

If you want a branch-only or method-only run (e.g. you find the line numbers noisy in CI and only care about whether
each conditional was exercised), enable the criterion you want and then disable line coverage:

```ruby
SimpleCov.start do
  enable_coverage :branch
  disable_coverage :line
end
```

If you disable every criterion, `SimpleCov.start` raises `SimpleCov::ConfigurationError` — at least one of `:line`,
`:branch`, or `:method` must remain enabled.

### Branch coverage

Branch coverage records whether each branch of a condition executed, not just whether a line ran.

```ruby
SimpleCov.start do
  enable_coverage :branch
end
```

It's handy for one-line conditionals:

```ruby
number.odd? ? "odd" : "even"
```

Line coverage always marks this line as executed, but never tells you whether both arms were taken. Guard clauses have
the same story:

```ruby
return if number.odd?

# more code
```

If the whole method is covered you still won't know whether the guard ever triggered — line coverage just sees the
condition evaluated.

In the HTML report, lines are annotated as `branch_type: hit_count`:

* `then: 2` — the `then` branch (of an `if`) was executed twice
* `else: 0` — the `else` branch (of an `if` or `case`) was never executed

Even if you don't write an `else` branch, it still shows up: a missed implicit `else` means the `if` condition was
never false, or no `when` of a `case` matched.

**Is branch coverage strictly better?** No. Branch coverage only concerns itself with conditionals — coverage of
sequential code is of no interest to it. A file with no conditional logic has no branch data, and SimpleCov reports its
0-of-0 branches as 100% (everything coverable was covered). So look at both metrics together: missing 10% of your lines
might account for 50% of your branches.

#### Ignoring implicit `else` branches

Ruby's `Coverage` library reports an `:else` branch for several constructs even when the source has no literal `else`
keyword — exhaustive `case/in` pattern matches, `case/when` without an `else` arm, `||=` / `&&=`, and `if` / `unless`
without an `else`. Those synthetic branches show up as missed and depress the branch-coverage percentage despite there
being no code to test. If your style relies on exhaustive pattern matching (or you just want `||=` to stop tanking
coverage), opt out:

```ruby
SimpleCov.start do
  enable_coverage :branch
  ignore_branches :implicit_else
end
```

`ignore_branches` is variadic; `:implicit_else` and `:eval_generated` (below) are the supported tokens. Calling it
before (or without) `enable_coverage :branch` is harmless: the setting is stored and applies once branch coverage is
enabled. Explicit `else` arms still count.

#### Ignoring eval-generated branches and methods

Rails' `delegate` (and other macros that call `module_eval(body, __FILE__, __LINE__)`) make Ruby's `Coverage` library
attribute the eval'd code to the macro's source line. The result is a `delegate :foo, to: :bar` line that surfaces in
the report as if it had its own `def foo` and an `if` branch — both reported as missed when the delegated method isn't
called from the suite. Drop those synthetic entries:

```ruby
SimpleCov.start do
  enable_coverage :branch
  enable_coverage :method
  ignore_branches :eval_generated
  ignore_methods :eval_generated
end
```

`ignore_methods` is variadic; `:eval_generated` is the only supported token. Both filters detect eval-generated entries
by walking the static source with [Prism](https://github.com/ruby/prism) and dropping any Coverage entry whose start
line lacks a real `def` keyword (for methods) or branch construct (for branches). Prism is bundled with Ruby 3.3+; on
older Rubies `gem install prism` enables the filter, otherwise it's a silent no-op. Real `def`s and branches that share
a line with an eval-generated entry are kept (line-presence is the matcher).

### Oneshot lines coverage

Oneshot lines coverage is a faster alternative to line coverage.

Traditional coverage records *how many times* each line ran. Often it's enough to know *whether* each line ran at
least once — and the counting just adds overhead. Oneshot coverage records only the first execution of each line; the
hook for each line fires once, after which the program runs with zero overhead.

```ruby
SimpleCov.start do
  enable_coverage :oneshot_line
  primary_coverage :oneshot_line
end
```

### Eval coverage

You can measure coverage for code evaluated by `Kernel#eval`. Supported in CRuby 3.2+.

```ruby
SimpleCov.start do
  enable_coverage :eval
end
```

This is typically useful for ERB. Set `ERB#filename=` so SimpleCov can trace the original `.erb` source file.

### Primary coverage

By default the primary coverage type is `line`. The primary type determines what comes first in all output, and which
type is checked when you customize exit behavior without naming a type (e.g. `SimpleCov.minimum_coverage 90`). To change
it:

```ruby
SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end

# or, outside a block:
SimpleCov.primary_coverage :branch
```

Coverage must first be enabled for non-default types.

## Filters

Filters remove selected files from your coverage data.

### Default filters

`SimpleCov.start` loads four filters out of the box:

* **`root_filter`** — drops every file outside of `SimpleCov.root`, so you don't end up with coverage reports for the
  source files of every gem in your bundle. (See [Covering files outside the root](#covering-files-outside-the-root).)
* **`bundler_filter`** — drops `/vendor/bundle/` (in case a project keeps its gems checked into the repo).
* **`hidden_filter`** — drops any path that starts with a dot, matching the regex `/\A\..*/`. This is what hides
  `.bundle/`, `.semaphore-cache/`, and similar dotfile directories — but it also hides legitimate top-level directories
  like `.scripts/`. If you keep code in such a directory, remove this filter (see below).
* **`test_frameworks`** — drops common test directories (`test/`, `spec/`, `features/`, `autotest/`), matching the
  regex `%r{\A(test|features|spec|autotest)/}`. Running the test suite always executes 100% of the test files
  themselves, which inflates the overall percentage and obscures application coverage. Remove this filter if you
  prefer to see test files in the report (e.g. to surface dead helpers).

For a clean slate (no defaults at all), `require 'simplecov/no_defaults'` *before* `require 'simplecov'`, or call
`SimpleCov.clear_filters` from your config block. To drop a specific default while keeping the others, use
`remove_filter`:

```ruby
SimpleCov.start do
  remove_filter(/\A\..*/) # restore coverage for .scripts/, .tooling/, etc.
end
```

`remove_filter` matches by value, so pass back the same `String` or `Regexp` the default profile used. For filters
added with a block, pass the same `Proc` object you originally handed to `skip`.

### Defining custom filters

Define your own filters to remove configuration files, tests, or anything else you don't need in the report. A filter
can be a String or Regexp (Regexp-matched against each source file's path), a block, your own Filter class, or an array
of any of these.

#### String filter

```ruby
SimpleCov.start do
  skip "/test/"
end
```

Removes all files whose path matches "/test/".

#### Regex filter

```ruby
SimpleCov.start do
  skip %r{^/test/}
end
```

Removes all files whose path starts with /test/.

#### Block filter

```ruby
SimpleCov.start do
  skip do |source_file|
    source_file.lines.count < 5
  end
end
```

Block filters receive a `SimpleCov::SourceFile` and return `true` to remove the file or `false` to keep it. (See the
RDoc for `SimpleCov::SourceFile` for the available methods.) The example above removes files with fewer than 5 lines.

#### Custom filter class

```ruby
class LineFilter < SimpleCov::Filter
  def matches?(source_file)
    source_file.lines.count < filter_argument
  end
end

SimpleCov.skip LineFilter.new(5)
```

Inherit from `SimpleCov::Filter` and define `matches?(source_file)`; a `true` return removes the file. The
`filter_argument` is set in the `SimpleCov::Filter` initializer — `5` in this example.

#### Array filter

```ruby
SimpleCov.start do
  proc = Proc.new { |source_file| false }
  skip ["string", /regex/, proc, LineFilter.new(5)]
end
```

Pass an array containing any of the other filter types.

### Ignoring/skipping code

Disable coverage for a span of code with `# simplecov:disable` and `# simplecov:enable` comments. The available
categories are `line`, `branch`, and `method`; combine them with commas, and omit them to target all three. Anything
trailing the directive is treated as a free-form reason and ignored — no separator is required, though `--` or any
other marker is fine if you prefer one.

```ruby
# simplecov:disable line
def skipped_lines
  never_reached
end
# simplecov:enable line

# simplecov:disable branch, method legacy adapter, scheduled for removal
class LegacyAdapter
  def call(value)
    value ? :yes : :no
  end
end
# simplecov:enable

raise "absurd" # simplecov:disable
```

Inline directives (trailing real code) only affect the line they sit on. Block directives sit on their own line and
remain in effect until the matching `# simplecov:enable` for the same category — or end of file if never closed.
Directive markers inside string literals or heredocs are ignored.

> [!WARNING]
> The older `# :nocov:` toggle still works but is **deprecated** and will be removed in a future release. Each file
> that uses it emits a one-time deprecation warning pointing at the recommended `# simplecov:disable` /
> `# simplecov:enable` replacement. The configurable token name (`SimpleCov.nocov_token`) is similarly deprecated.

> [!NOTE]
> You shouldn't have to skip private methods that are included in your coverage. If you appropriately test the public
> interface of your classes and objects, you should automatically get full coverage of your private methods.

### How `cover` and `skip` interact

`cover` and `skip` operate on different sides of the same chain. `skip` (and its deprecated `add_filter` alias) drops
matching files from the report. `cover` declares a positive scope that restricts the final report to files matching at
least one `cover` matcher.

Order: `skip` runs first, then `cover`. A file matched by any `skip` filter is dropped before `cover` is consulted, so
a file matched by both is dropped, not kept. The two are not commutative.

```ruby
SimpleCov.start do
  cover "{app,lib}/**/*.rb"
  skip  "app/legacy"
end
```

That config covers `app/` and `lib/`, then drops `app/legacy/`. With only `cover` and no overlapping `skip`, every
configured default filter (hidden files, vendored gems, test directories) still applies — `cover` doesn't bypass them.
Use `no_default_skips` to opt out of the defaults wholesale before adding your own.

`cover` also expands string-glob matchers on disk so files that exist but were never `require`'d during the run still
appear in the report (at 0% coverage). Regexp and Proc cover matchers don't trigger disk discovery — they only filter
the universe of files that Ruby's `Coverage` library reported.

### Covering files outside the root

The `root_filter` drops every file outside of `SimpleCov.root` from the raw coverage data before any other filters or
groups run, so paths you might want to track (a Rails Engine installed as a gem, sibling directories in a Docker
layout, etc.) never reach your filter chain. To include them, widen `SimpleCov.root` to a directory that contains both
the project and the extra paths — `'/'` works when there's no useful common ancestor — and then express the
inclusion/exclusion as filters or groups:

```ruby
SimpleCov.root '/'
SimpleCov.start :rails do
  skip { |src| !src.filename.start_with?(Rails.root.to_s, '/path/to/my_engine') }
end
```

## Groups

Separate your source files into groups — for example, a Rails app might list Models, Controllers, Helpers, and Libs
separately. Group definition works like filters (and also accepts custom filter classes), but a source file ends up in
a group when the filter *passes* (returns `true`), as opposed to being excluded from results when a filter returns
`true`.

```ruby
SimpleCov.start do
  group "Models", "app/models"
  group "Controllers", "app/controllers"
  group "Long files" do |src_file|
    src_file.lines.count > 100
  end
  group "Multiple Files", ["app/models", "app/controllers"] # You can also pass in an array
  group "Short files", LineFilter.new(5) # Using the LineFilter class defined in the Filters section above
end
```

## Profiles

By default, SimpleCov's only assumption is that you want coverage for files inside your project root. To avoid
repetitive configuration, you can use predefined blocks of configuration called 'profiles', or define your own. Pass a
profile's name as the first argument to `SimpleCov.start`.

SimpleCov bundles a `rails` profile that looks roughly like this:

```ruby
SimpleCov.profiles.define 'rails' do
  skip '/test/'
  skip '/config/'

  group 'Controllers', 'app/controllers'
  group 'Models', 'app/models'
  group 'Helpers', 'app/helpers'
  group 'Libraries', 'lib'
end
```

It's just a `SimpleCov.configure` block. Launch it from your test helper, optionally adding more config:

```ruby
SimpleCov.start 'rails'

# or

SimpleCov.start 'rails' do
  # additional config here
end
```

### The `strict` profile

For projects that have already reached full coverage (or want to ratchet up to it), the bundled `strict` profile
enables line, branch, and method coverage and pins each minimum threshold at 100%:

```ruby
SimpleCov.start 'strict'
```

That's equivalent to:

```ruby
SimpleCov.start do
  enable_coverage :branch
  enable_coverage :method
  enable_coverage :eval if Coverage.respond_to?(:supported?) && Coverage.supported?(:eval)
  minimum_coverage line: 100, branch: 100, method: 100
end
```

The profile drops the branch / method clauses on engines that don't support those criteria (JRuby), so it still loads
cleanly there, enforcing line coverage at 100%. `:eval` is included on Ruby 3.2+ (where the runtime supports it), so
any code reached through `Kernel#eval` — typically ERB templates with `ERB#filename=` set — is held to the same 100%
bar. On older Rubies, the `:eval` clause is silently skipped.

### Custom profiles

Load additional profiles with `SimpleCov.load_profile('xyz')`. This lets you build on an existing profile and reuse
it across unit tests and Cucumber features:

```ruby
# lib/simplecov_custom_profile.rb
require 'simplecov'
SimpleCov.profiles.define 'myprofile' do
  load_profile 'rails'
  skip 'vendor' # Don't include vendored stuff
end

# features/support/env.rb
require 'simplecov_custom_profile'
SimpleCov.start 'myprofile'

# test/test_helper.rb
require 'simplecov_custom_profile'
SimpleCov.start 'myprofile'
```

### Profile plugin gems

If `SimpleCov.start "<name>"` doesn't find a profile registered under `<name>`, the bundled profile loader tries to
autoload one in two steps: first `require "simplecov/profiles/<name>"` (where bundled profiles like `rails` and
`strict` live), then `require "simplecov-profile-<name>"` (the conventional name for a third-party plugin gem). Either
require is expected to call `SimpleCov.profiles.define "<name>" do ... end` so the registered block can be applied. If
both requires fail or neither registers the profile, `SimpleCov.start` raises `SimpleCov::ConfigurationError`.

To publish your own profile as a gem, name it `simplecov-profile-<name>` and have its main file call
`SimpleCov.profiles.define`:

```ruby
# In a gem named simplecov-profile-myteam
SimpleCov.profiles.define "myteam" do
  enable_coverage :branch
  cover "{app,lib}/**/*.rb"
  skip  "app/legacy"
end
```

A user who adds the gem to their Gemfile can then `SimpleCov.start "myteam"` without explicitly requiring it.

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

In a parallel run, the process that writes the final report waits for the other workers to finish and write their
result sets before merging. It gives up after `SimpleCov.parallel_wait_timeout` seconds (default 60) and reports
whatever has arrived, skipping the minimum / maximum coverage checks against that partial total. If one worker runs
much heavier test files and routinely finishes a minute or more after the others, raise it with
`SimpleCov.parallel_wait_timeout 180` so its coverage is included.

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
  coordination.
- **`GenericAdapter`** — catch-all for any runner that follows the `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` env-var
  convention but doesn't ship a Ruby API (parallel_rspec, knapsack-style splitters, custom CI sharding scripts).
  Activates when `TEST_ENV_NUMBER` is set and no more-specific adapter is.

Adapters are tried in registration order; the first whose `active?` returns `true` is chosen. With both built-ins, this
means parallel_tests users get the precise gem-based path and parallel_rspec (or any env-var-only runner) gets the
polling-based fallback without any configuration change. See #1065.

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

## Coverage thresholds and exit behavior

Define what SimpleCov does when your test suite finishes by customizing the `at_exit` hook. The default is shown below;
do whatever you like instead:

```ruby
SimpleCov.at_exit do
  SimpleCov.result.format!
end
```

The threshold settings below make SimpleCov exit non-zero when coverage doesn't meet your expectations, so they double
as CI gates.

### Per-criterion thresholds with `coverage`

The `coverage` block configures each criterion (line, branch, method) the same way: because the criterion is fixed by
the enclosing block, every threshold value is a plain percentage, so line, branch, and method coverage read identically.
Naming a criterion also enables it (line is enabled by default).

```ruby
SimpleCov.start do
  coverage :line do
    minimum           90    # suite-wide minimum; SimpleCov exits non-zero if unmet
    minimum_per_file  80    # per-file minimum
    minimum_per_file  100, only: "app/mailers/request_mailer.rb"  # per-path override (String path or Regexp)
    minimum_per_group 95, only: "Models"                          # minimum for a named group
    maximum_drop      5     # exit non-zero if coverage drops more than 5% between runs
  end

  coverage :branch, minimum: 80    # one-liner form for a single setting
  coverage :method, minimum: 100
end
```

| Verb | Effect |
|------|--------|
| `minimum N` | Suite-wide minimum for this criterion. |
| `maximum N` | Suite-wide maximum: fails if coverage rises above N. Pairs with `minimum` to pin coverage so an unexpected jump fails instead of being silently absorbed. |
| `exact N` | Pins coverage by setting both `minimum` and `maximum` to N. |
| `maximum_drop N` | Maximum allowed drop between runs (`maximum_drop 0` refuses any drop). |
| `minimum_per_file N` | Per-file minimum. Add `only: "path"` / `only: %r{regexp}` to override it for matching files (later, more specific overrides win). |
| `minimum_per_group N, only: "Name"` | Minimum for a named [group](#groups). |

Every verb is also a keyword on the one-liner form (`coverage :branch, minimum: 80, maximum_drop: 5`). Two more options:
`coverage :line, oneshot: true` selects the faster [oneshot-lines mode](#oneshot-lines-coverage), and
`coverage :branch, primary: true` makes branch the report's leading criterion (the one a bare `minimum_coverage 90`
targets). `coverage :eval` enables [eval coverage](#eval-coverage).

### Suite-wide shortcuts

For the common case of a single suite-wide threshold, the flat helpers are convenient sugar over the block above. A bare
number targets the primary criterion (line by default); a Hash sets per-criterion values:

```ruby
SimpleCov.minimum_coverage 90                      # primary criterion (line)
SimpleCov.minimum_coverage line: 90, branch: 80
SimpleCov.maximum_coverage line: 90
SimpleCov.maximum_coverage_drop line: 5, branch: 10
SimpleCov.expected_coverage 95.42                  # pins minimum == maximum
SimpleCov.refuse_coverage_drop :line, :branch      # maximum drop of 0
```

`expected_coverage` floors the actual percentage to two decimal places, so an actual of 95.4287 still passes at
`expected_coverage 95.42`.

> [!NOTE]
> `minimum_coverage_by_file` and `minimum_coverage_by_group` are **deprecated** in favor of the `coverage` block's
> `minimum_per_file` / `minimum_per_group`. They still work but emit a deprecation warning. For example, replace
> `minimum_coverage_by_file line: 70, 'app/x.rb' => 100` with:
>
> ```ruby
> coverage :line do
>   minimum_per_file 70
>   minimum_per_file 100, only: "app/x.rb"
> end
> ```

## Formatters

### Using your own formatter

```ruby
SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
```

`SimpleCov.result.format!` then invokes `SimpleCov::Formatter::YourFormatter.new.format(result)`, where `result` is a
`SimpleCov::Result`. Do whatever you wish with it.

### Using multiple formatters

As of SimpleCov 0.9 you can specify multiple result formats. The HTML and JSON formatters are built in; other
formatters ship as separate gems you'll need to add and require — for example,
[simplecov-cobertura](https://github.com/dashingrocket/simplecov-cobertura) for the Cobertura XML that many CI services
consume.

```ruby
require "simplecov-cobertura"

SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::CoberturaFormatter,
]
```

### JSON formatter

`SimpleCov::Formatter::JSONFormatter` emits JSON — useful for CI consumption or reporting to external services.

```ruby
SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
```

By default `coverage.json` carries the full source-text array for every file, which makes the payload self-contained
but dominates the file size on larger projects. Tools that read the project's source files directly from disk can opt
out of that field with:

```ruby
SimpleCov.start do
  source_in_json false
end
```

The HTML report's `coverage_data.js` always retains the source array — the client-side viewer renders source from
there. The setting only affects the side-file `coverage.json`. When the source is omitted, `meta.commit` (the git
commit SHA the report was generated against) lets tools recover the exact source lines from repository history.

> The JSON formatter was originally a separate gem,
> [simplecov_json_formatter](https://github.com/codeclimate-community/simplecov_json_formatter). It is now built in and
> loaded by default; existing code that does `require "simplecov_json_formatter"` will continue to work.

### JSON Schema for `coverage.json`

`coverage.json` is a public contract, described by a JSON Schema (2020-12) so downstream tools can validate it,
generate types, or pin to a known shape. Every emitted document carries a top-level `$schema` URL pointing at the
versioned canonical, plus a human-readable `meta.schema_version` (`"major.minor"`).

The **versioned canonical** lives at [`schemas/coverage-v1.0.schema.json`](schemas/coverage-v1.0.schema.json) and
long-lived integrations should pin to it. Once a SimpleCov release ships with a given versioned schema file, that file
is immutable: bug fixes, additions, or shape changes ship as a new versioned file (a minor or major bump), never as a
silent rewrite of an already-released one. Schemas may still be corrected in-place between gem releases — i.e., the
schema file as it currently exists on `main` may change before the next gem release, but the schema for any published
gem version stays frozen. A convenience alias at [`schemas/coverage.schema.json`](schemas/coverage.schema.json) always
tracks the latest and may shift when a new SimpleCov release bumps the schema.

The schema version is independent of the gem version:

- Additive changes (new fields) bump the **minor** segment. Existing consumers keep working.
- Removals or shape changes bump the **major** segment, and ship as a new `schemas/coverage-vX.0.schema.json` file so
  v1.x consumers stay valid.

The current version is **1.0**. Top-level structure:

```jsonc
{
  "$schema":  "https://raw.githubusercontent.com/simplecov-ruby/simplecov/main/schemas/coverage-v1.0.schema.json",
  "meta":     { /* schema_version, simplecov_version, command_name, project_name, timestamp, root, commit, line_coverage, branch_coverage, method_coverage */ },
  "total":    { /* aggregate stats for lines (and branches / methods when enabled) */ },
  "coverage": { "<project-relative path>": { /* per-file lines, source, branches, methods, etc. */ } },
  "groups":   { "<group name>": { /* per-group stats + files */ } },
  "errors":   { /* minimum_coverage, minimum_coverage_by_file, minimum_coverage_by_group, maximum_coverage, maximum_coverage_drop violations */ }
}
```

The `.resultset.json` file is **not** schema'd — it's SimpleCov-internal and may change shape across releases. Build
integrations on top of `coverage.json`.

### More formatters, editor integrations, and hosted services

  * [Open Source formatter and integration plugins for SimpleCov](doc/alternate-formatters.md)
  * [Editor Integration](doc/editor-integration.md)
  * [Hosted (commercial) services](doc/commercial-services.md)

## Output and diagnostics

### Errors and exit statuses

If an error is raised, SimpleCov prints a message to `STDERR` with the exit status, to aid debugging:

```
SimpleCov failed with exit 1
```

Disable this message with:

```ruby
SimpleCov.print_errors false
```

### Color output

When color is enabled, SimpleCov highlights coverage percentages in its `STDERR` diagnostics by band (green for
`>= 90%`, yellow for `>= 75%`, red below) and prints the "SimpleCov failed with exit ..." summary in red. By default,
color is on only when `STDERR` is a TTY. Two environment variables override that:

- `NO_COLOR=1` (any non-empty value) disables color even when stderr is a TTY. Honors the
  [no-color.org](https://no-color.org) convention.
- `FORCE_COLOR=1` (any non-empty value) enables color even when stderr is not a TTY. Useful when stderr is piped through
  a wrapper that itself renders ANSI in a terminal (`parallel_tests --combine-stderr`, log multiplexers, some CI runners).

`NO_COLOR` wins if both are set.

For programmatic control, use `SimpleCov.color`. An explicit `true` or `false` wins over the env vars and TTY detection:

```ruby
SimpleCov.color true   # always on
SimpleCov.color false  # always off
SimpleCov.color :auto  # default behavior: NO_COLOR/FORCE_COLOR/TTY
```

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

Pass `--input PATH` to read a non-default `coverage.json`. `--json` emits the totals as a JSON object keyed by section
name (`"All Files"` plus each group), useful when a CI step needs to act on the numbers rather than display them.

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

Regressions are listed first. Pass `--fail-on-drop` to exit non-zero when any file's line coverage slipped, so this
composes with CI as a "coverage of this PR didn't drop" gate even when overall thresholds are still satisfied.
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

### `serve` and `clean`

`simplecov serve` serves the coverage report over HTTP — handy on a remote box where you can't open files directly.
`--port N` binds to a specific port (default: a random open port) and `--host HOST` to a specific host (default
`127.0.0.1`).

`simplecov clean` removes the coverage report directory. `--dry-run` prints what would be removed without deleting
anything; `-q` / `--quiet` suppresses status lines.

## Compatibility and troubleshooting

### Ruby version compatibility

SimpleCov is built in [Continuous Integration] on Ruby 3.1+ and JRuby 9.4+. On CRuby, every coverage criterion
described above is available on the supported versions, with one exception: [eval coverage](#eval-coverage) requires
CRuby 3.2+.

### JRuby

On JRuby, only **line coverage** is available — branch, method, oneshot-line, and eval coverage rely on features of
CRuby's `Coverage` library that JRuby doesn't implement. SimpleCov detects this automatically: the bundled `strict`
profile, for instance, enforces only line coverage at 100% on JRuby instead of failing to load.

To get accurate line numbers in coverage results, JRuby needs its full backtrace enabled. Pass `JRUBY_OPTS="--debug"`,
or create a `.jrubyrc` with `debug.fullTrace=true`.

### Notes on specific frameworks and test utilities

Some frameworks and tools have quirks worth knowing about when using SimpleCov:

<table>
  <tr><th>Framework</th><th>Notes</th><th>Issue</th></tr>
  <tr>
    <th>
      parallel_tests
    </th>
    <td>
      As of 0.8.0, SimpleCov should correctly recognize parallel_tests and
      supplement your test suite names with their corresponding test env
      numbers. SimpleCov locks the resultset cache while merging, ensuring no
      race conditions occur when results are merged.
    </td>
    <td>
      <a href="https://github.com/simplecov-ruby/simplecov/issues/64">#64</a> &amp;
      <a href="https://github.com/simplecov-ruby/simplecov/pull/185">#185</a>
    </td>
  </tr>
  <tr>
    <th>
      knapsack_pro
    </th>
    <td>
      To make SimpleCov work with Knapsack Pro Queue Mode to split tests in parallel on CI jobs you need to provide CI node index number to the <code>SimpleCov.command_name</code> in <code>KnapsackPro::Hooks::Queue.before_queue</code> hook.
    </td>
    <td>
      <a href="https://knapsackpro.com/faq/question/how-to-use-simplecov-in-queue-mode">Tip</a>
    </td>
  </tr>
  <tr>
    <th>
      RubyMine
    </th>
    <td>
      The <a href="https://www.jetbrains.com/ruby/">RubyMine IDE</a> has
      built-in support for SimpleCov's coverage reports, though you might need
      to explicitly set the output root using `SimpleCov.root('foo/bar/baz')`
    </td>
    <td>
      <a href="https://github.com/simplecov-ruby/simplecov/issues/95">#95</a>
    </td>
  </tr>
  <tr>
    <th>
      Spork
    </th>
    <td>
      Because of how Spork works internally (using preforking), there used to
      be trouble when using SimpleCov with it, but that has apparently been
      resolved with a specific configuration strategy. See <a
      href="https://github.com/simplecov-ruby/simplecov/issues/42#issuecomment-4440284">this</a>
      comment.
    </td>
    <td>
      <a href="https://github.com/simplecov-ruby/simplecov/issues/42#issuecomment-4440284">#42</a>
    </td>
  </tr>
  <tr>
    <th>
      Spring
    </th>
    <td>
      <a href="#using-spring-with-simplecov">See section below.</a>
    </td>
    <td>
      <a href="https://github.com/simplecov-ruby/simplecov/issues/381">#381</a>
    </td>
  </tr>
  <tr>
    <th>
      Test/Unit
    </th>
    <td>
      Test Unit 2 used to mess with ARGV, leading to a failure to detect the
      test process name in SimpleCov. <code>test-unit</code> releases 2.4.3+
      (Dec 11th, 2011) should have this problem resolved.
    </td>
    <td>
      <a href="https://github.com/simplecov-ruby/simplecov/issues/45">#45</a> &amp;
      <a href="https://github.com/test-unit/test-unit/pull/12">test-unit/test-unit#12</a>
    </td>
  </tr>
</table>

### Using Spring with SimpleCov

If you use [Spring](https://github.com/rails/spring) to speed up test runs, SimpleCov often misreports coverage with the
default config due to an eager-loading issue. There are a few fixes.

One solution is to [explicitly call eager
load](https://github.com/simplecov-ruby/simplecov/issues/381#issuecomment-347651728) in your `test_helper.rb` /
`spec_helper.rb` after calling `SimpleCov.start`:

```ruby
require 'simplecov'
SimpleCov.start 'rails'
Rails.application.eager_load!
```

Alternatively, disable Spring while running SimpleCov:

```sh
DISABLE_SPRING=1 rake test
```

Or remove `gem 'spring'` from your `Gemfile`.

### Different coverage between local and CI

Rails generates `config/environments/test.rb` with `config.eager_load = ENV["CI"].present?` (Rails 7+), so **CI eagerly
loads every file in `app/` while your local run does not**. The two environments then report different file sets and
different totals from the same suite. Two ways to make the report deterministic:

- Set `config.eager_load = true` everywhere in `test.rb` (slower locally, but matches CI — and matches what users
  actually see in production).
- Stick with the `rails` profile, which folds `{app,lib}/**/*.rb` into the report at 0% on every run regardless of
  `eager_load`. (The profile resolves the glob relative to `SimpleCov.root`, not the test runner's cwd.) Outside the
  profile, the equivalent is `cover "{app,lib}/**/*.rb"` — see the
  [legacy-API migration table](#migrating-from-the-legacy-configuration-api) for the relationship with the older
  `track_files`.

### Missing coverage

The **most common problem is that SimpleCov isn't required and started before everything else**. To track coverage for
your whole application, **SimpleCov must come first** so that it (and the underlying Coverage library) can track files
as they're loaded and used.

If coverage is missing for some code, a simple trick is to add a `puts` inside that file and another right after
`SimpleCov.start`, then check the order they print in:

```ruby
# my_code.rb
class MyCode

  puts "MyCode is being loaded!"

  def my_method
    # ...
  end
end

# spec_helper.rb / rails_helper.rb / test_helper.rb / .simplecov — whatever
SimpleCov.start
puts "SimpleCov started successfully!"
```

If you see this order, you're good:

```
SimpleCov started successfully!
MyCode is being loaded!
```

If `MyCode is being loaded!` prints first, the file was loaded before SimpleCov started — that's your problem.

### Upgrading from 0.x

Four methods that had been deprecated for a decade or more were removed in 1.0. Each had a one-to-one rename:

| Removed                                  | Use instead                                |
| ---------------------------------------- | ------------------------------------------ |
| `SimpleCov::Filter#passes?`              | `SimpleCov::Filter#matches?`               |
| `SimpleCov.adapters`                     | `SimpleCov.profiles`                       |
| `SimpleCov.load_adapter('rails')`        | `SimpleCov.load_profile('rails')`          |
| `SimpleCov::Formatter::MultiFormatter[]` | `SimpleCov::Formatter::MultiFormatter.new` |

If a custom filter still defines `passes?`, rename the method to `matches?` — the signature and semantics are identical.

## Related projects

Want to find dead code in production? Try [Coverband](https://github.com/danmayer/coverband).

## Contributing

* [Issue Tracker](https://github.com/simplecov-ruby/simplecov/issues) — for code and bug reports. See
  [CONTRIBUTING](https://github.com/simplecov-ruby/simplecov/blob/main/CONTRIBUTING.md) for how to contribute, along
  with common problems to check before creating an issue.
* [Mailing List](https://groups.google.com/forum/#!forum/simplecov) — open list for discussion and announcements on
  Google Groups.

## Code of Conduct

Everyone participating in this project's development, issue trackers, and other channels is expected to follow our
[Code of Conduct](./CODE_OF_CONDUCT.md).

## Kudos

Thanks to Aaron Patterson for the original idea for this!

## Copyright

Copyright (c) 2010-2026 Erik Berlin, Benjamin Fleischer, Akira Matsuda, Christoph Olszowka, Tobias Pfeiffer, David Rodríguez, and Xavier Shay. See MIT-LICENSE for details.
