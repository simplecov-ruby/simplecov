Unreleased
==========

## Breaking Changes
* JSON formatter: group stats changed from `{ "covered_percent": 80.0 }` to full stats shape `{ "covered": 8, "missed": 2, "total": 10, "percent": 80.0, "strength": 0.0 }`. The key `covered_percent` is renamed to `percent`.
* JSON formatter: `simplecov_json_formatter` gem is now built in. `require "simplecov_json_formatter"` continues to work via a shim.
* `StringFilter` now matches at path-segment boundaries. `"lib"` matches `/lib/` but no longer matches `/library/`. Use a `Regexp` filter for substring matching.
* `SourceFile#project_filename` now returns a truly relative path with no leading separator (e.g. `lib/foo.rb` instead of `/lib/foo.rb`). This also removes the leading `/` from file path keys in `coverage.json` and from the filename in `minimum_coverage_by_file` error messages. Anchored `RegexFilter`s that relied on a leading `/` (e.g. `%r{^/lib/}`) should be rewritten (e.g. `%r{\Alib/}`).
* Removed `docile` gem dependency. The `SimpleCov.configure` DSL block is now evaluated via `instance_exec` with instance variable proxying.
* Removed automatic activation of `JSONFormatter` when the `CC_TEST_REPORTER_ID` environment variable is set. The default `HTMLFormatter` now emits `coverage.json` alongside the HTML report (using `JSONFormatter.build_hash` to serialize the same payload `JSONFormatter` writes), so the env-var special case is no longer needed.
* `SimpleCov.start` now loads the `test_frameworks` profile by default, which filters paths under `test/`, `spec/`, `features/`, and `autotest/`. Running the suite always executes 100% of the test files themselves, which inflated the overall percentage and obscured application coverage. To opt back in (e.g. to surface dead test helpers), drop the filter with `remove_filter %r{\A(test|features|spec|autotest)/}`. See #816.
* HTML and JSON formatters now write the "Coverage report generated for X to Y" status line (and the per-criterion totals beneath it) to stderr instead of stdout. The message is a diagnostic, not the program's output, and routing it to stdout polluted pipelines like `rspec -f json`. Suppress it entirely with `silent: true` on the formatter; redirect with `2>&1` if you want the old behavior. See #1060.

## Deprecations
* Calling `SimpleCov.start` from `.simplecov` is deprecated. Coverage tracking still begins for backward compatibility, but a one-time deprecation warning fires pointing the user at moving the call into `spec_helper.rb` / `test_helper.rb`; a future release will require the explicit `SimpleCov.start` from a test helper. The migration goes hand-in-hand with the bugfix below: once `SimpleCov.start` lives in the test helper, the parent process that auto-loads `.simplecov` never starts tracking and the empty-report-overwrite scenario can't arise. See #581.
* `# :nocov:` toggle comments (and the configurable `SimpleCov.nocov_token` / `SimpleCov.skip_token`) are deprecated in favor of the new `# simplecov:disable` / `# simplecov:enable` directives. Each file that still uses `# :nocov:` emits a one-time deprecation warning to stderr at load time pointing at the recommended replacement, and any call to `SimpleCov.nocov_token` or `SimpleCov.skip_token` (getter or setter) likewise warns. The directive will be removed in a future release.

## Enhancements
* `SimpleCov.minimum_coverage_by_file` now accepts per-path overrides alongside the existing per-criterion defaults: pass String or Regexp keys to declare file- or directory-specific thresholds, e.g. `minimum_coverage_by_file line: 70, 'app/mailers/request_mailer.rb' => 100`. A String ending in `/` matches as a directory prefix; otherwise it must equal the project-relative path. Regexp keys match against the project-relative path. Per-path values may be a Numeric (primary criterion) or a per-criterion Hash; for each file the effective threshold is the defaults merged with any matching overrides (later overrides win per criterion, overrides win over defaults). The new overrides surface in `coverage.json` under the existing `errors.minimum_coverage_by_file` block. See #575.
* Added `SimpleCov.maximum_coverage` (and the convenience `SimpleCov.expected_coverage`, which sets `minimum_coverage` and `maximum_coverage` to the same value) so the suite can be pinned to an exact coverage figure. A drop fails per the minimum; an unexpected increase also fails, prompting you to bump the threshold up rather than silently absorbing the improvement. Accepts the same Numeric / per-criterion Hash forms as `minimum_coverage`. Exits with status 4 (`SimpleCov::ExitCodes::MAXIMUM_COVERAGE`) when violated, and surfaces in `coverage.json` under `errors.maximum_coverage`. Comparisons floor the actual percent to two decimal places, so `expected_coverage 95.42` still passes when the actual is e.g. 95.4287. See #187.
* Added a bundled `strict` profile (`SimpleCov.start "strict"`) that enables line, branch, and method coverage and pins the minimum threshold for each at 100%. Drops to line-only on engines without branch/method support (JRuby). See #1061.
* `SimpleCov.coverage_path` is now explicitly settable rather than always computed from `SimpleCov.root + SimpleCov.coverage_dir`. Setting it pins the report destination regardless of later `root` / `coverage_dir` changes — useful for out-of-tree build directories (CMake/CTest etc.) where the coverage report doesn't live under the source root. See #716.
* The "Coverage report generated for X to Y" status line now prints the report path relative to the current working directory when it lives under cwd, and includes the entry-point filename — `coverage/index.html` from the HTML formatter, `coverage/coverage.json` from the JSON formatter — so the line points at a concrete file (and is clickable in terminals that hyperlink paths). Paths outside cwd stay absolute. See #197.
* Added `SimpleCov.disable_coverage(criterion)` so a project can opt out of line coverage entirely — e.g. `enable_coverage :branch; disable_coverage :line` for a branch-only run. `SimpleCov.start` now raises `SimpleCov::ConfigurationError` when every criterion has been disabled. The formatter summary and JSON output emit only the criteria that were actually measured, so a branch-only run produces no `Line coverage:` line, no `lines` key in `coverage.json`, and no zero-padded line numbers in the HTML report. See #845.
* Added `SimpleCov.remove_filter(arg)` to drop a specific filter (matching by `filter_argument`) and `SimpleCov.clear_filters` to wipe the entire chain. Useful for selectively turning off one of the defaults loaded by `SimpleCov.start` — e.g. `remove_filter(/\A\..*/)` to stop hiding paths that begin with a dot. The README's "Default filters" section enumerates what's loaded by default and how to disable each piece. See #803.
* Terminal output is now colorized when stderr is a TTY: coverage percentages in the formatter summary line and threshold-violation messages are rendered green (>= 90%), yellow (>= 75%), or red (< 75%) — matching the HTML report's thresholds. The "SimpleCov failed with exit N…" line is red and the "Stopped processing SimpleCov…" line is yellow. Respects `NO_COLOR` (force off, per no-color.org) and `FORCE_COLOR` (force on); `NO_COLOR` wins if both are set. See #1157.
* CLI subcommands `coverage`, `report`, `uncovered`, and `diff` now colorize their printed percentages by the same threshold (and `diff` colors regressions red, improvements green). Auto-detect based on whether stdout is a TTY; the same `NO_COLOR` / `FORCE_COLOR` env vars apply. Each subcommand also accepts a `--no-color` flag as a per-invocation override.
* Added `# simplecov:disable` / `# simplecov:enable` directive comments for selectively skipping `line`, `branch`, and `method` coverage. Block form (own line) opens a region until the matching `# simplecov:enable`; inline form (trailing a code line) skips just that line. Categories may be combined (`# simplecov:disable line, branch`); omitting categories targets all three. Any trailing text is treated as a free-form reason and discarded (e.g. `# simplecov:disable line legacy adapter`). Directive markers inside string literals or heredocs are ignored.
* JSON formatter: `meta.timestamp` is now emitted with millisecond precision (`iso8601(3)`) so the concurrent-overwrite warning can distinguish writes within the same wall-clock second
* JSON formatter: added `total` section with aggregate coverage statistics (covered, missed, total, percent, strength) for line, branch, and method coverage. Line stats additionally include `omitted` (count of blank/comment lines, i.e. lines that cannot be covered)
* JSON formatter: per-file output now includes `total_lines`, `lines_covered_percent`, and when enabled: `branches_covered_percent`, `methods` array, and `methods_covered_percent`
* JSON formatter: group stats now include full statistics for all enabled coverage types, not just line coverage percent
* JSON formatter: added `silent:` keyword to `JSONFormatter.new` to suppress console output
* Merged `simplecov-html` formatter into the main gem. A backward-compatibility shim ensures `require "simplecov-html"` still works.
* Merged `simplecov_json_formatter` into the main gem. A backward-compatibility shim ensures `require "simplecov_json_formatter"` still works.
* `CommandGuesser` now appends the framework name to parallel test data (e.g. `"RSpec (1/2)"` instead of `"(1/2)"`)

## Bugfixes
* `SimpleCov::Result` now warns when it drops source files because their absolute paths aren't on the local filesystem, instead of silently producing an empty `0 / 0 (100.00%)` report. The most common trigger is `SimpleCov.collate` invoked from a machine or working directory different from where the individual resultsets were generated — when *every* entry is missing the warning explicitly names that case and points at the issue; when only some are missing the warning is quieter and lists up to five paths with a `(+N more)` suffix. See #980.
* Files added via `track_files` that were never loaded now use the same line classification as loaded files. Previously, `SimulateCoverage` ran the file through `LinesClassifier`, which marks every non-blank, non-comment line as relevant — so a multi-line method chain `@x = a.foo.bar` reported 4 relevant lines for the unloaded copy and 2 for the loaded copy, throwing off per-file and overall percentages. `SimulateCoverage` now uses `Coverage.line_stub` (the same stub Ruby would have produced if the file were required), then overlays `# :nocov:` toggles and `# simplecov:disable line` directive ranges that the runtime doesn't know about. The two paths now agree on every shape: multi-line statements, `end` keywords, blank lines, and SimpleCov-specific exclusion comments. Some projects will see their `tracked_files` percentages shift as a result. See #654.
* Fix the parent-process / subprocess race where a Rakefile (or Rails `Bundler.require`) caused `.simplecov` to auto-load `SimpleCov.start` in the rake parent, which then shelled out to a test runner subprocess; the subprocess wrote a correct report, then the parent's `at_exit` would clobber it with an empty 0% report. Three layers of defense now apply: (1) `.simplecov` is treated as configuration only and no longer starts tracking from the parent (see Deprecations); (2) `ResultMerger.store_result` merges incoming entries with same-`command_name` entries that were written after our `process_start_time` instead of overwriting them; (3) `SimpleCov.at_exit_behavior` defers entirely when our merged result is empty and `coverage/.last_run.json` is fresher than this process. See #581.
* Don't report misleading 100% branch/method coverage for files added via `track_files` that were never loaded. See #902
* Fix HTML formatter tab bar layout: dark mode toggle no longer wraps onto two lines, and tabs connect seamlessly with the content panel
* Allow `SimpleCov.root('/')` so files outside the conventional project root can be tracked (e.g. Docker layouts where code and tests are siblings at `/`). The root-prefix regex no longer doubles the separator (`//`), and `project_name` no longer crashes when `root` has no parent segment. The user-facing `:root_filter` profile and the unconditional `UselessResultsRemover` now share a single regex source instead of computing it independently. See #860.
* When `SimpleCov.start` runs after `require "minitest/autorun"` (e.g. under `Rake::TestTask` or `Minitest::TestTask`, which shell out as `ruby -e 'require "minitest/autorun"; ...'`), automatically set `external_at_exit` and route the report through `Minitest.after_run`. Previously, the `at_exit` LIFO order meant SimpleCov formatted a 0% report before Minitest ran. The opposite ordering (SimpleCov first) is still handled by `lib/minitest/simplecov_plugin.rb`. See #1032, #1099, and #1112.

0.22.1 (2024-09-02)
==========

## Enhancements

* You can now define `minimum_coverage_by_group` - See https://github.com/simplecov-ruby/simplecov/pull/1105. Thanks [@mikhliuk-k](https://github.com/mikhliuk-k)!
* `minimum_coverage_by_file` prints the name of the violating file. - [@philipritchey](https://github.com/philipritchey)

0.22.0 (2022-12-23)
==========

## Enhancements
* On Ruby 3.2+, you can now use the new Coverage library feature for `eval` - See https://github.com/simplecov-ruby/simplecov/pull/1037. Thanks [@mame](https://github.com/mame)!

## Bugfixes
* Fix for making the test suite pass against the upcoming Ruby 3.2 - See https://github.com/simplecov-ruby/simplecov/pull/1035. Thanks [@mame](https://github.com/mame)

0.21.2 (2021-01-09)
==========

## Bugfixes
* `maximum_coverage_drop` won't fail any more if `.last_run.json` is still in the old format. Thanks [@petertellgren](https://github.com/petertellgren)
* `maximum_coverage_drop` won't fail if an expectation is specified for a previous unrecorded criterion, it will just pass (there's nothing, so nothing to drop)
* fixed bug in `maximum_coverage_drop` calculation that could falsely report it had dropped for minimal differences

0.21.1 (2021-01-04)
==========

## Bugfixes
* `minimum_coverage_by_file` works again as expected (errored out before 😱)

0.21.0 (2021-01-03)
==========

The "Collate++" release making it more viable for big CI setups by limiting memory consumption. Also includes some nice new additions for branch coverage settings.

## Enhancements
* Performance of `SimpleCov.collate` improved - it should both run faster and consume much less memory esp. when run with many files (memory consumption should not increase with number of files any more)
* Can now define the minimum_coverage_by_file, maximum_coverage_drop and refuse_coverage_drop by branch as well as line coverage. Thanks to [@jemmaissroff](https://github.com/jemmaissroff)
* Can set primary coverage to something other than line by setting `primary_coverage :branch` in SimpleCov Configuration. Thanks to [@jemmaissroff](https://github.com/jemmaissroff)

## Misc
* reduce gem size by splitting Changelog into `Changelog.md` and a pre 0.18 `Changelog.old.md`, the latter of which is not included in the gem
* The interface of `ResultMeger.merge_and_store` is changed to support the `collate` performance improvements mentioned above. It's not considered an official API, hence this is not in the breaking section. For people using it to merge results from different machines, it's recommended to migrate to [collate](https://github.com/simplecov-ruby/simplecov#merging-test-runs-under-different-execution-environments).

0.20.0 (2020-11-29)
==========

The "JSON formatter" release. Starting now a JSON formatter is included by default in the release. This is mostly done for Code Climate reasons, you can find more details [in this issue](https://github.com/codeclimate/test-reporter/issues/413).
Shipping with so much by default is sub-optimal, we know. It's the long term plan to also provide `simplecov-core` without the HTML or JSON formatters for those who don't need them/for other formatters to rely on.

## Enhancements
* `simplecov_json_formatter` included by default ([docs](https://github.com/simplecov-ruby/simplecov#json-formatter)), this should enable the Code Climate test reporter to work again once it's updated
* invalidate internal cache after switching `SimpleCov.root`, should help with some bugs

0.19.1 (2020-10-25)
==========

## Bugfixes

* No more warnings triggered by `enable_for_subprocesses`. Thanks to [@mame](https://github.com/mame)
* Avoid trying to patch `Process.fork` when it isn't available. Thanks to [@MSP-Greg](https://github.com/MSP-Greg)

0.19.0 (2020-08-16)
==========

## Breaking Changes
* Dropped support for Ruby 2.4, it reached EOL

## Enhancements
* observe forked processes (enable with SimpleCov.enable_for_subprocesses). See [#881](https://github.com/simplecov-ruby/simplecov/pull/881), thanks to [@robotdana](https://github.com/robotdana)
* SimpleCov distinguishes better that it stopped processing because of a previous error vs. SimpleCov is the originator of said error due to coverage requirements.

## Bugfixes
* Changing the `SimpleCov.root` combined with the root filtering didn't work. Now they do! Thanks to [@deivid-rodriguez](https://github.com/deivid-rodriguez) and see [#894](https://github.com/simplecov-ruby/simplecov/pull/894)
* in parallel test execution it could happen that the last coverage result was written to disk when it didn't complete yet, changed to only write it once it's the final result
* if you run parallel tests only the final process will report violations of the configured test coverage, not all previous processes
* changed the parallel_tests merging mechanisms to do the waiting always in the last process, should reduce race conditions

## Noteworthy
* The repo has moved to https://github.com/simplecov-ruby/simplecov - everything stays the same, redirects should work but you might wanna update anyhow
* The primary development branch is now `main`, not `master` anymore. If you get simplecov directly from github change your reference. For a while `master` will still be occasionally updated but that's no long term solion.

0.18.5 (2020-02-25)
===================

Can you guess? Another bugfix release!

## Bugfixes
* minitest won't crash if SimpleCov isn't loaded - aka don't execute SimpleCov code in the minitest plugin if SimpleCov isn't loaded. Thanks to [@edariedl](https://github.com/edariedl) for the report of the peculiar problem in [#877](https://github.com/simplecov-ruby/simplecov/issues/877).

0.18.4 (2020-02-24)
===================

Another small bugfix release 🙈 Fixes SimpleCov running with rspec-rails, which was broken due to our fixed minitest integration.

## Bugfixes
* SimpleCov will run again correctly when used with rspec-rails. The excellent bug report [#873](https://github.com/simplecov-ruby/simplecov/issues/873) by [@odlp](https://github.com/odlp) perfectly details what went wrong. Thanks to [@adam12](https://github.com/adam12) for the fix [#874](https://github.com/simplecov-ruby/simplecov/pull/874).


0.18.3 (2020-02-23)
===========

Small bugfix release. It's especially recommended to upgrade simplecov-html as well because of bugs in the 0.12.0 release.

## Bugfixes
* Fix a regression related to file encodings as special characters were missing. Furthermore we now respect the magic `# encoding: ...` comment and read files in the right encoding. Thanks ([@Tietew](https://github.com/Tietew)) - see [#866](https://github.com/simplecov-ruby/simplecov/pull/866)
* Use `Minitest.after_run` hook to trigger post-run hooks if `Minitest` is present. See [#756](https://github.com/simplecov-ruby/simplecov/pull/756) and [#855](https://github.com/simplecov-ruby/simplecov/pull/855) thanks ([@adam12](https://github.com/adam12))

0.18.2 (2020-02-12)
===================

Small release just to allow you to use the new simplecov-html.

## Enhancements
* Relax simplecov-html requirement so that you're able to use [0.12.0](https://github.com/simplecov-ruby/simplecov-html/blob/main/CHANGELOG.md#0120-2020-02-12)

0.18.1 (2020-01-31)
===================

Small Bugfix release.

## Bugfixes
* Just putting `# :nocov:` on top of a file or having an uneven number of them in general works again and acts as if ignoring until the end of the file. See [#846](https://github.com/simplecov-ruby/simplecov/issues/846) and thanks [@DannyBen](https://github.com/DannyBen) for the report.

0.18.0 (2020-01-28)
===================

Huge release! Highlights are support for branch coverage (Ruby 2.5+) and dropping support for EOL'ed Ruby versions (< 2.4).
Please also read the other beta patch notes.

You can run with branch coverage by putting `enable_coverage :branch` into your SimpleCov configuration (like the `SimpleCov.start do .. end` block)

## Enhancements
* You can now define the minimum expected coverage by criterion like `minimum_coverage line: 90, branch: 80`
* Memoized some internal data structures that didn't change to reduce SimpleCov overhead
* Both `FileList` and `SourceFile` now have a `coverage` method that returns a hash that points from a coverage criterion to a `CoverageStatistics` object for uniform access to overall coverage statistics for both line and branch coverage

## Bugfixes
* we were losing precision by rounding the covered strength early, that has been removed. **For Formatters** this also means that you may need to round it yourself now.
* Removed an inconsistency in how we treat skipped vs. irrelevant lines (see [#565](https://github.com/simplecov-ruby/simplecov/issues/565)) - SimpleCov's definition of 100% is now "You covered everything that you could" so if coverage is 0/0 that's counted as a 100% no matter if the lines were irrelevant or ignored/skipped

## Noteworthy
* `FileList` stopped inheriting from Array, it includes Enumerable so if you didn't use Array specific methods on it in formatters you should be fine
* We needed to change an internal file format, which we use for merging across processes, to accommodate branch coverage. Sadly CodeClimate chose to use this file to report test coverage. Until a resolution is found the code climate test reporter won't work with SimpleCov for 0.18+, see [this issue on the test reporter](https://github.com/codeclimate/test-reporter/issues/413).

0.18.0.beta3 (2020-01-20)
========================

## Enhancements
* Instead of ignoring old `.resultset.json`s that are inside the merge timeout, adapt and respect them

## Bugfixes
* Remove the constant warning printing if you still have a `.resultset.json` in pre 0.18 layout that is within your merge timeout

0.18.0.beta2 (2020-01-19)
===================

## Enhancements
* only turn on the requested coverage criteria (when activating branch coverage before SimpleCov would also instruct Ruby to take Method coverage)
* Change how branch coverage is displayed, now it's `branch_type: hit_count` which should be more self explanatory. See [#830](https://github.com/simplecov-ruby/simplecov/pull/830) for an example and feel free to give feedback!
* Allow early running exit tasks and avoid the `at_exit` hook through the `SimpleCov.run_exit_tasks!` method. (thanks [@macumber](https://github.com/macumber))
* Allow manual collation of result sets through the `SimpleCov.collate` entrypoint. See the README for more details (thanks [@ticky](https://github.com/ticky))
* Within `case`, even if there is no `else` branch declared show missing coverage for it (aka no branch of it). See [#825](https://github.com/simplecov-ruby/simplecov/pull/825)
* Stop symbolizing all keys when loading cache (should lead to be faster and consume less memory)
* Cache whether we can use/are using branch coverage (should be slightly faster)

## Bugfixes
* Fix a crash that happened when an old version of our internal cache file `.resultset.json` was still present

0.18.0.beta1 (2020-01-05)
===================

This is a huge release highlighted by changing our support for ruby versions to 2.4+ (so things that aren't EOL'ed) and finally adding branch coverage support!

This release is still beta because we'd love for you to test out branch coverage and get your feedback before doing a full release.

On a personal note from [@PragTob](https://github.com/PragTob/) thanks to [ruby together](https://rubytogether.org/) for sponsoring this work on SimpleCov making it possible to deliver this and subsequent releases.

## Breaking
* Dropped support for all EOL'ed rubies meaning we only support 2.4+. Simplecov can no longer be installed on older rubies, but older simplecov releases should still work. (thanks [@deivid-rodriguez](https://github.com/deivid-rodriguez))
* Dropped the `rake simplecov` task that "magically" integreated with rails. It was always undocumented, caused some issues and [had some issues](https://github.com/simplecov-ruby/simplecov/issues/689#issuecomment-561572327). Use the integration as described in the README please :)

## Enhancements

* Branch coverage is here! Please try it out and test it! You can activate it with `enable_coverage :branch`. See the README for more details. This is thanks to a bunch of people most notably [@som4ik](https://github.com/som4ik), [@tycooon](https://github.com/tycooon), [@stepozer](https://github.com/stepozer),  [@klyonrad](https://github.com/klyonrad) and your humble maintainers also contributed ;)
* If the minimum coverage is set to be greater than 100, a warning will be shown. See [#737](https://github.com/simplecov-ruby/simplecov/pull/737) (thanks [@belfazt](https://github.com/belfazt))
* Add a configuration option to disable the printing of non-successful exit statuses. See [#747](https://github.com/simplecov-ruby/simplecov/pull/746) (thanks [@JacobEvelyn](https://github.com/JacobEvelyn))
* Calculating 100% coverage is now stricter, so 100% means 100%. See [#680](https://github.com/simplecov-ruby/simplecov/pull/680) thanks [@gleseur](https://github.com/gleseur)

## Bugfixes

* Add new instance of `Minitest` constant. The `MiniTest` constant (with the capital T) will be removed in the next major release of Minitest. See [#757](https://github.com/simplecov-ruby/simplecov/pull/757) (thanks [@adam12](https://github.com/adam12))

Older Changelogs
================

Looking for older changelogs? Please check the [old Changelog](https://github.com/simplecov-ruby/simplecov/blob/main/CHANGELOG.old.md)
