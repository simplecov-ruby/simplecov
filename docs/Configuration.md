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
| `minimum_coverage_by_file line: 70, 'app/x.rb' => 100` | `coverage(:line) { minimum 70, per: :file; minimum 100, per: 'app/x.rb' }` | The `coverage` block fixes the criterion and the `per:` argument carries the scope, so per-path overrides are plain percentages instead of a hash mixing Symbol / String / Regexp keys. See [Per-criterion thresholds](#per-criterion-thresholds-with-coverage). |
| `minimum_coverage_by_group 'Models' => { line: 90 }` | `coverage(:line) { minimum 90, per: group('Models') }` | Same uniform shape as the per-file form. |

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

### Enforcing migrations with `deprecations :raise`

Deprecated spellings warn and keep working, which also means a project can run on them indefinitely without noticing.
Once you have migrated (or when starting fresh), make any deprecated API an error instead:

```ruby
SimpleCov.start do
  deprecations :raise
end
```

Every deprecation then raises a `SimpleCov::ConfigurationError` naming the replacement, so CI fails the moment an old
spelling creeps back in, and early adopters can hold themselves to the current surface as the DSL evolves (see the
[configuration roadmap](Configuration_Roadmap.md)). The default is `deprecations :warn`. There is deliberately no
silencing mode, because a deprecation you cannot see is a migration you never make.

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
  coverage :branch do
    ignore :implicit_else
  end
end
```

`ignore` is variadic; `:implicit_else` and `:eval_generated` (below) are the supported branch tokens, and naming the
criterion enables it, so no separate `enable_coverage :branch` is needed. Explicit `else` arms still count. The flat
`ignore_branches` / `ignore_methods` setters are **deprecated** in favor of the criterion-scoped verb; they still work
(and, unlike the block, record the setting without enabling the criterion) but warn with the replacement.

#### Ignoring eval-generated branches and methods

Rails' `delegate` (and other macros that call `module_eval(body, __FILE__, __LINE__)`) make Ruby's `Coverage` library
attribute the eval'd code to the macro's source line. The result is a `delegate :foo, to: :bar` line that surfaces in
the report as if it had its own `def foo` and an `if` branch — both reported as missed when the delegated method isn't
called from the suite. Drop those synthetic entries:

```ruby
SimpleCov.start do
  coverage :branch, ignore: :eval_generated
  coverage :method, ignore: :eval_generated
end
```

`:eval_generated` is the only supported method token. Both filters detect eval-generated entries
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

This is typically useful for ERB. Set `ERB#filename=` so SimpleCov can trace the original `.erb` source file. In a
Rails application, use [`cover_views`](#view-coverage) instead, which handles that wiring for you.

### View coverage

`cover_views` brings ActionView templates into the report:

```ruby
SimpleCov.start "rails" do
  cover_views
end
```

It defaults to `app/views/**/*.{erb,haml,slim}`. Pass globs of your own (expanded against `SimpleCov.root`) for
templates that live somewhere else:

```ruby
cover_views "app/views/**/*.erb", "app/components/**/*.erb"
```

Templates are measured through eval coverage, which `cover_views` enables, so this needs CRuby 3.2 or later. No
`ERB#filename=` wiring is required: ActionView already compiles each template with the template's own path as the eval
identifier, at an offset that cancels the wrapper it generates, so the coverage data lands on the template file at its
own line numbers.

Every template language with a registered ActionView handler works the same way, because the handler generates Ruby
that keeps the template's line structure and the compile goes through the same path a render does. Haml and Slim need
nothing beyond their gems being loaded, and a language your project registers a handler for itself is covered by
naming its extension in a glob. Extensions with no handler registered are left out of the report rather than reported
as untested, which is what keeps the default glob's `.haml` and `.slim` harmless in a project that has neither.

Templates that no test renders are never compiled, and so would be missing from the report entirely rather than
reported as untested. To avoid a report that flatters exactly the views nobody covered, SimpleCov compiles them at the
end of the run, without rendering them, which lists them at 0%.

Templates are ordinary files in the report: `skip` excludes them, the `rails` profile files them under a `Views`
group, and the source view highlights each one in its own language, so the markup reads as markup and the code in it
as Ruby.

Two things to expect the first time you turn this on. Overall coverage usually drops, because untested views are being
counted for the first time. And because eval coverage is now on, macros that evaluate code with `__FILE__` and
`__LINE__` (Rails' `delegate`, and anything else built on `class_eval`) start reporting methods and branches at the
line of the macro call. `coverage :method, ignore: :eval_generated` and `coverage :branch, ignore: :eval_generated` drop those.

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

## Tracking which test covers each line

Coverage is normally a union over the whole suite. `track_tests` records the other half of the data: which test
executed each covered line. It is opt-in because it has a real cost. Coverage is sampled around every test, and the
recorded map takes space in `.resultset.json`.

```ruby
SimpleCov.start do
  track_tests
end
```

RSpec examples and Minitest tests are wrapped automatically, in any load order. Under minitest 5 the bundled minitest
plugin installs the wrapper, and under minitest 6 (whose autorun no longer discovers plugins) SimpleCov installs it
the moment `Minitest::Test` is defined. Each test is identified by the location of its definition, such as
`spec/user_spec.rb:42` or `test/user_test.rb:17`, relative to `SimpleCov.root`. Any other runner can wrap its own
units of work with the same primitive the built-in integrations use:

```ruby
SimpleCov.track_test("test/legacy_suite.rb:12") do
  run_the_test
end
```

The recorded map rides along in `.resultset.json` under a versioned `contexts` key beside the coverage, and is
exposed on the result:

```ruby
result = SimpleCov::ResultMerger.merged_result
result.contexts.covering("lib/simplecov/result.rb", 42)
# => ["spec/result_spec.rb:42", "spec/result_spec.rb:57"]
```

The data layer speaks of contexts rather than tests because the mechanism is general (coverage.py calls the same
idea dynamic contexts, and a future Coverage library feature would likely use the same word). Under `track_tests`
every context is one test. `covering` accepts absolute or project-relative paths and answers with the sorted ids,
and `contexts` lists every recorded id, including tests whose runs covered nothing new.

The map also flows into `coverage.json`, the JSON formatter's schema'd public artifact, as a document-level
`contexts` array of ids plus per-file hex bitmaps of the lines each context executed. That is the durable form
downstream tools should build on (the resultset is an internal cache). See
[the coverage.json schema](Formatters.md#json-schema-for-coveragejson), version 1.1.

The HTML report renders the recording in the source view. A covered line no recorded test executed drains from
green to a slate tint ("Covered outside tests" in the legend), which is how coverage that only load time, suite
setup, or a helper produced stops passing for tested code at a glance. Every executed line carries a tests badge
at its right edge; clicking it (or focusing it and pressing Enter) opens an inline panel naming the covering
tests, the same ids in the same order `simplecov tests file:line` prints, ready to select and hand to a runner.
The file header's Line coverage row splits its fraction by the same attribution, "Line coverage: 100.00% 21/30
relevant lines covered by tests, 9/30 relevant lines covered outside tests", and the legend's covered chip splits
to match: green "Covered by tests" beside the slate "Covered outside tests".

The file list carries the same distinction. Each line coverage bar splits its fill into the share recorded tests
produced (in the usual green/yellow/red band colour) and a slate share covered only outside them, so a file whose
100% rests mostly on load-time execution looks different from one its tests actually exercise. Sorting by line
coverage breaks ties on that share: descending, a file 90% covered by tests ranks above one at 80% when both sit
at 100% line coverage. A report generated without `track_tests` shows none of this.

When results are merged, across suites, parallel workers, or `simplecov collate`, the maps are merged by the same
rule everywhere: the merged result carries the union of the maps when every merged result recorded one, and no map at
all otherwise. A partial map would present one worker's tests as the whole run's, so mixing tracked and untracked
results drops the map and says so on stderr. `Result#contexts` is nil in that case.

Recording costs one coverage snapshot per context boundary. The snapshot copies every criterion the run measures
for every file the process loaded, so its price scales with what you enable: with line coverage alone it is a
millisecond or two even in a large app, while branch and method coverage make each snapshot an order of magnitude
more expensive, since their tables dominate the copy. Two levers control the total. Run `track_tests` in a
lines-only configuration when you can. And when per-test precision costs more than it is worth, coarsen the
granularity:

```ruby
SimpleCov.start do
  track_tests granularity: :file
end
```

At `:file` granularity every test in a file shares one context (ids like `spec/user_spec.rb`, no line number), and
because consecutive tests with the same context share a single open recording segment, the suite pays one snapshot
per change of file in run order instead of one per test. How much that saves depends on the runner's ordering: RSpec
runs each spec file's groups together, so the cost approaches one snapshot per file, while Minitest shuffles test
classes globally, so a suite with many small classes still changes file often (though far less often than it changes
test). `covering` then answers with test files rather than individual tests, which is still exactly what test
selection needs.

Three constraints follow from how the map is recorded. It needs per-line execution counts, so `track_tests` raises at
startup under `enable_coverage :oneshot_line` (a line reports only its first hit ever, which would attribute it to
one test). Only files under `SimpleCov.root` are attributed, since diffing every loaded gem on every test is what
would make tracking unaffordable. And tests running concurrently in threads inside one process (Minitest's
`parallelize_me!`, Rails' `parallelize(with: :threads)`) cannot be told apart, because coverage counters are
process-global, so such a process warns, stops recording, and stores no map rather than a misattributed one.
Process-parallel runners are fine, since each worker records and stores its own map.

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

The `coverage` block configures each criterion (line, branch, method) the same way: the criterion is fixed by the
enclosing block, so every threshold value is a plain number, and the scope is a uniform `per:` argument, so line,
branch, and method coverage read identically. Naming a criterion also enables it (line is enabled by default).

```ruby
SimpleCov.start do
  coverage :line do
    minimum 90                          # suite-wide minimum; SimpleCov exits non-zero if unmet
    minimum 80,  per: :file             # per-file minimum
    minimum 100, per: "app/mailers/request_mailer.rb"  # per-path override (String path or Regexp)
    minimum 95,  per: group("Models")   # minimum for a named group
    maximum_drop 5                      # exit non-zero if coverage drops more than 5% between runs
    maximum_missed 12                   # at most 12 uncovered lines across the whole suite
    maximum_missed 5, per: :file        # no single file may carry more than 5 uncovered lines
  end

  coverage :branch, minimum: 80    # one-liner form for a single setting
  coverage :method, minimum: 100
end
```

| Verb | Effect |
|------|--------|
| `minimum N` | Minimum for this criterion. Bare, it applies suite-wide. `per: :file` sets the default applied to every file, `per: "path"` / `per: %r{regexp}` overrides that default for matching files (later, more specific overrides win), and `per: group("Name")` sets the minimum for a named [group](#groups). |
| `maximum N` | Suite-wide maximum: fails if coverage rises above N. Pairs with `minimum` to pin coverage so an unexpected jump fails instead of being silently absorbed. |
| `exact N` | Pins coverage by setting both `minimum` and `maximum` to N. |
| `maximum_drop N` | Maximum allowed drop between runs (`maximum_drop 0` refuses any drop). |
| `maximum_missed N` | Cap on the number of misses, in the criterion's own units (uncovered lines, branch arms, or methods). Bare, it caps the whole suite: an absolute burn-down number rather than a ratio, since "12 uncovered lines left" stays meaningful as the codebase grows and shrinks and a percentage cannot say it. With `per: :file` (or a path target) it caps each file: a percent minimum systematically flatters big files (a 2,000-line file at 99% hides 20 misses while a 10-line file at 80% fails over 2), while the cap holds every file to the same absolute budget. Files with a [baseline](#per-file-baseline-ratchet) entry are exempt from the per-file cap per covered criterion, the same way they are from the per-file minimum. |

Every suite-wide verb is also a keyword on the one-liner form (`coverage :branch, minimum: 80, maximum_drop: 5`).
Two more options: `coverage :line, oneshot: true` selects the faster [oneshot-lines mode](#oneshot-lines-coverage),
and `coverage :branch, primary: true` makes branch the report's leading criterion (the one a bare
`minimum_coverage 90` targets). `coverage :eval` enables [eval coverage](#eval-coverage).

> [!NOTE]
> The suffixed scope verbs (`minimum_per_file`, `minimum_per_group`, `maximum_missed_per_file`, and their `only:`
> keyword) are **deprecated** in favor of the `per:` argument. They still work but emit a deprecation warning naming
> the exact replacement. The wider plan for the configuration DSL is recorded in the
> [configuration roadmap](Configuration_Roadmap.md).

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
SimpleCov.maximum_missed 12                        # at most 12 misses suite-wide
```

`expected_coverage` floors the actual percentage to two decimal places, so an actual of 95.4287 still passes at
`expected_coverage 95.42`.

> [!NOTE]
> `minimum_coverage_by_file` and `minimum_coverage_by_group` are **deprecated** in favor of the `coverage` block's
> scoped `minimum`. They still work but emit a deprecation warning. For example, replace
> `minimum_coverage_by_file line: 70, 'app/x.rb' => 100` with:
>
> ```ruby
> coverage :line do
>   minimum 70,  per: :file
>   minimum 100, per: "app/x.rb"
> end
> ```

### Per-file baseline (ratchet)

On a legacy codebase, one per-file minimum does nothing useful: set it to what the worst file scores and every
other file is allowed to sink to that level. The baseline gives each file its own floor instead, generated from the
current state and checked in:

```sh
bundle exec rspec          # produce a report
simplecov ratchet          # write .simplecov_baseline.yml from it
git add .simplecov_baseline.yml
```

The file maps each path to the coverage it has already reached, per measured criterion:

```yaml
lib/simplecov/legacy_thing.rb:
  lines:
    percent: 41.2
    missed: 137
lib/simplecov/result.rb:
  lines:
    percent: 100.0
    missed: 0
```

From then on the exit check fails any listed file that drops below its own floor, and `simplecov ratchet` (run after
improving coverage) rewrites the file with floors only ever tightening, so touching a legacy file drags it upward and
it can never slide back. The diff on the baseline file becomes the honest record of which direction the codebase
moved, reviewable in the same PR as the change that moved it. This is `.rubocop_todo.yml` applied to coverage.

Each floor carries two numbers because each covers for the other's blind spot. The percent is the policy, but a
percent moves when a file is edited without any coverage change at all, so the missed count acts as the dampener: a
file below its percent floor still passes while it carries no more misses than the floor recorded. A violation
requires both a lower percent and more misses. A hand-written entry can be a bare percent (`lib/foo.rb: 41.2`), which
is then decided by the percent alone until the next ratchet records its missed count.

Files with an entry are exempt from the per-file minimum (per criterion), and files without one fall through to it, so
new code is held to the real standard rather than to a grandfathered one. Ratchet never adds entries for new files for
the same reason. Entries for deleted files are pruned, and `simplecov ratchet --init` regenerates the whole file from
scratch when you deliberately want floors reset.

The baseline lives at `.simplecov_baseline.yml` under `SimpleCov.root`. Its presence is the opt-in; point somewhere
else with:

```ruby
SimpleCov.baseline_file "config/coverage_floors.yml"
```

To ratchet automatically at the end of every run instead of by deliberate `simplecov ratchet` invocations, add
[`SimpleCov::Formatter::BaselineFormatter`](Formatters.md#baseline-formatter) to your formatters.



[Configuration]: http://rubydoc.info/gems/simplecov/SimpleCov/Configuration "Configuration options API documentation"
