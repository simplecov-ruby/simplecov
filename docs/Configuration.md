# Configuring SimpleCov

Everything you set up before a run: configuration formats, coverage criteria, filters, groups, profiles, and coverage thresholds.

*Part of the [SimpleCov](../README.md) documentation.*

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

Zero-parameter configuration blocks run with `self` set to the SimpleCov configuration target. To call helpers or use
instance variables from the surrounding object, accept the target explicitly; parameterized blocks keep their normal
`self`:

```ruby
SimpleCov.configure do |config|
  config.minimum_coverage coverage_threshold
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
> `Bundler.require` would leave an empty parent-process report that overwrites the test subprocess's good one. See
> [#581](https://github.com/simplecov-ruby/simplecov/issues/581).

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
| `formatter false` / `formatters []` | Opt out of formatting entirely. Workers in big parallel CI runs only need their `.resultset.json` for a final `SimpleCov.collate` step; skipping the formatter saves the per-job HTML / multi-formatter overhead. See [#964](https://github.com/simplecov-ruby/simplecov/issues/964). |
| `parallel_tests true` / `false`     | Force on / off the auto-require of the `parallel_tests` gem. Default (unset) auto-detects from `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` and silently skips if the gem isn't installed. Set explicitly when you use those env vars for unrelated subprocess coordination. See [#1018](https://github.com/simplecov-ruby/simplecov/issues/1018). |

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

Line coverage is on by default. You can additionally enable branch, method, and eval coverage, replace ordinary line
coverage with oneshot-line coverage, and choose which criterion leads the report.

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

Ordinary and oneshot line coverage are mutually exclusive. `enable_coverage :oneshot_line` replaces `:line`; calling
`enable_coverage :line` later switches back. When both appear in one call, the last requested mode wins.

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

Files that match no configured group appear in an implicit `Ungrouped` group. That name is reserved; use another name
such as `Other` for an explicit group.

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



[Configuration]: http://rubydoc.info/gems/simplecov/SimpleCov/Configuration "Configuration options API documentation"
