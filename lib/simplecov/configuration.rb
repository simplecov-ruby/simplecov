# frozen_string_literal: true

require "fileutils"
require_relative "formatter/multi_formatter"

module SimpleCov
  #
  # Bundles the configuration options used for SimpleCov. All methods
  # defined here are usable from SimpleCov directly. Please check out
  # SimpleCov documentation for further info.
  #
  module Configuration
    attr_writer :filters, :groups, :formatter, :print_error_status

    #
    # The root for the project. This defaults to the
    # current working directory.
    #
    # Configure with SimpleCov.root('/my/project/path')
    #
    def root(root = nil)
      return @root if defined?(@root) && root.nil?

      @coverage_path = nil unless @coverage_path_explicit # invalidate cache
      @root = File.expand_path(root || Dir.getwd)
    end

    #
    # The name of the output and cache directory. Defaults to 'coverage'
    #
    # Configure with SimpleCov.coverage_dir('cov')
    #
    def coverage_dir(dir = nil)
      return @coverage_dir if defined?(@coverage_dir) && dir.nil?

      @coverage_path = nil unless @coverage_path_explicit # invalidate cache
      @coverage_dir = dir || "coverage"
    end

    #
    # Returns the full path to the output directory. By default this is
    # constructed from `SimpleCov.root` + `SimpleCov.coverage_dir` so
    # adjusting either of those propagates here, but you can override the
    # whole thing with an arbitrary absolute path — handy for out-of-tree
    # build directories (CMake/CTest setups etc.) where the coverage
    # report doesn't live under the source root:
    #
    #     SimpleCov.start do
    #       root '/foo'
    #       coverage_path '/tmp/build/coverage'
    #     end
    #
    # Either way, the directory is created if it doesn't yet exist.
    #
    # See https://github.com/simplecov-ruby/simplecov/issues/716.
    #
    def coverage_path(path = nil)
      if path
        @coverage_path = File.expand_path(path)
        @coverage_path_explicit = true
        FileUtils.mkdir_p @coverage_path
      end

      @coverage_path ||= begin
        computed = File.expand_path(coverage_dir, root)
        FileUtils.mkdir_p computed
        computed
      end
    end

    #
    # Restrict the universe of files in the coverage report to those matching
    # one or more globs, regexps, or block predicates. Multiple calls union;
    # when any `cover` matcher is configured the report drops every file that
    # doesn't match at least one of them.
    #
    # Strings are interpreted as shell globs (e.g. "lib/**/*.rb"), not
    # substring matches — this is a deliberate departure from the legacy
    # `add_filter` semantics and matches the way `track_files` already
    # interprets its argument.
    #
    # When the matcher is a string-glob, `cover` also expands the glob on
    # disk so files that exist but were never required during the run still
    # appear in the report (at 0% coverage). This is the "include unloaded
    # files" half of the legacy `track_files` behavior, rolled into the
    # same call.
    #
    #     SimpleCov.start do
    #       cover "lib/**/*.rb", "app/**/*.rb"
    #       cover(/_helper\.rb\z/)
    #       cover { |sf| sf.lines.count > 5 }
    #     end
    #
    def cover(*args, &block)
      args.each { |arg| cover_filters << build_cover_filter(arg) }
      cover_filters << SimpleCov::BlockFilter.new(block) if block
      cover_filters
    end

    #
    # Returns the list of configured inclusion filters added via `cover`.
    #
    def cover_filters
      @cover_filters ||= []
    end

    #
    # Returns the list of string globs passed to `cover` — used by the
    # disk-discovery pass in `SimpleCov.add_not_loaded_files` so files
    # matching a `cover` glob appear in the report even when they were
    # never required during the suite.
    #
    # Walks into `ArrayFilter` entries (built when a caller passes an
    # array to `cover`) so a glob nested inside `cover(["lib/**/*.rb",
    # /helper\.rb\z/])` still drives unloaded-file discovery.
    #
    def cover_globs
      collect_cover_globs(cover_filters)
    end

    #
    # DEPRECATED: prefer `cover`, which both includes unloaded files (the
    # historical `track_files` behavior) and restricts the report to the
    # matching set.
    #
    # Coverage results will always include files matched by this glob, whether
    # or not they were explicitly required. Without this, un-required files
    # will not be present in the final report.
    #
    def track_files(glob)
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.track_files` is deprecated. " \
           "#{track_files_replacement_hint(glob)}"
      @tracked_files = glob
    end

    # `track_files(nil)` is the documented way to clear a previously-set
    # glob, but `cover(nil)` raises `ConfigurationError`, so don't point
    # users at it. The `cover` API has no direct equivalent for "reset
    # the inclusion list" — `clear_filters` and `no_default_skips`
    # operate on the skip chain, not the cover chain. Point users at the
    # `@cover_filters` reset instead.
    def track_files_replacement_hint(glob)
      if glob.nil?
        "Replace with `SimpleCov.cover_filters.clear` — clearing the inclusion list."
      else
        "Replace with `SimpleCov.cover #{glob.inspect}` — `cover` includes unloaded files on disk " \
          "(the historical `track_files` behavior) and also restricts the report to the matching set. " \
          "If you want to keep additional files outside #{glob.inspect} in the report, pass every " \
          "directory you care about, e.g. `cover #{glob.inspect}, \"app/**/*.rb\"`."
      end
    end

    #
    # Returns the glob that will be used to include files that were not
    # explicitly required.
    #
    def tracked_files
      @tracked_files if defined?(@tracked_files)
    end

    #
    # Returns the list of configured exclusion filters added via `skip`
    # (or the deprecated `add_filter`).
    #
    def filters
      @filters ||= []
    end

    # The name of the command (a.k.a. Test Suite) currently running. Used for result
    # merging and caching. It first tries to make a guess based upon the command line
    # arguments the current test suite is running on and should automatically detect
    # unit tests, functional tests, integration tests, rpsec and cucumber and label
    # them properly. If it fails to recognize the current command, the command name
    # is set to the shell command that the current suite is running on.
    #
    # You can specify it manually with SimpleCov.command_name("test:units") - please
    # also check out the corresponding section in README.rdoc
    def command_name(name = nil)
      @name = name unless name.nil?
      @name ||= SimpleCov::CommandGuesser.guess
      @name
    end

    #
    # Gets or sets the configured formatter. Pass `false` (or `nil`) to
    # opt out of formatting entirely — worker processes in big parallel
    # CI setups (see #964) only need their `.resultset.json` on disk so
    # a final `SimpleCov.collate` job can produce the report; running
    # them without a formatter saves the per-job HTML/multi-formatter
    # overhead.
    #
    #     SimpleCov.start do
    #       formatter SimpleCov::Formatter::SimpleFormatter   # one formatter
    #       formatter false                                   # no formatter
    #     end
    #
    def formatter(formatter = :__no_arg__)
      return @formatter if formatter == :__no_arg__

      @formatter = formatter || nil # normalize `false` to `nil`
    end

    #
    # Sets the configured formatters. Pass `[]` to opt out of formatting
    # entirely; see `formatter` for the rationale.
    #
    #     SimpleCov.start do
    #       formatters [SimpleCov::Formatter::SimpleFormatter,
    #                   SimpleCov::Formatter::HTMLFormatter]
    #       formatters []   # no formatter
    #     end
    #
    def formatters(formatters = :__no_arg__)
      return Array(formatter) if formatters == :__no_arg__

      self.formatters = formatters
      formatters
    end

    #
    # Sets the configured formatters. Equivalent to `formatters [...]` /
    # `formatters []`; the assignment form is what runs when the DSL block
    # uses `self.formatters = [...]`.
    #
    def formatters=(formatters)
      @formatter = formatters.empty? ? nil : SimpleCov::Formatter::MultiFormatter.new(formatters)
    end

    #
    # Get or set whether to print a non-success status line at the end of
    # the run when the suite fails a coverage threshold check. Defaults to
    # true. Called with no arguments returns the current value; called with
    # an explicit boolean assigns it.
    #
    #     SimpleCov.start do
    #       print_errors false
    #     end
    #
    def print_errors(value = :__no_arg__)
      return defined?(@print_error_status) ? @print_error_status : true if value == :__no_arg__

      @print_error_status = value
    end

    #
    # DEPRECATED: alias for `print_errors`. Same value, same behavior.
    # The `print_error_status=` setter is also still available (it's an
    # attr_writer on the same instance variable).
    #
    def print_error_status
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.print_error_status` is deprecated. " \
           "Replace with `SimpleCov.print_errors` (same value)."
      defined?(@print_error_status) ? @print_error_status : true
    end

    #
    # Certain code blocks (i.e. Ruby-implementation specific code) can be excluded from
    # the coverage metrics by wrapping it inside # :nocov: comment blocks. The nocov token
    # can be configured to be any other string using this.
    #
    # Configure with SimpleCov.nocov_token('skip') or it's alias SimpleCov.skip_token('skip')
    #
    # DEPRECATED: prefer `# simplecov:disable` / `# simplecov:enable` block comments
    # (see SimpleCov::Directive). The `# :nocov:` toggle and this configuration hook
    # will be removed in a future release.
    #
    def nocov_token(nocov_token = nil)
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.nocov_token` and `SimpleCov.skip_token` are deprecated. " \
           "Replace with `# simplecov:disable` / `# simplecov:enable` block comments."
      current_nocov_token(nocov_token)
    end
    alias skip_token nocov_token

    # Internal accessor used by SimpleCov to recognise `# :nocov:` markers
    # without emitting the public-API deprecation warning. Will be removed
    # alongside the deprecated `nocov_token` setter.
    def current_nocov_token(value = nil)
      return @nocov_token if defined?(@nocov_token) && value.nil?

      @nocov_token = value || "nocov"
    end

    #
    # Returns the configured groups. Add groups using SimpleCov.add_group
    #
    def groups
      @groups ||= {}
    end

    #
    # Returns the hash of available profiles
    #
    def profiles
      @profiles ||= SimpleCov::Profiles.new
    end

    #
    # Allows you to configure simplecov in a block instead of prepending SimpleCov to all config methods
    # you're calling.
    #
    #     SimpleCov.configure do
    #       add_filter 'foobar'
    #     end
    #
    # This is equivalent to SimpleCov.add_filter 'foobar' and thus makes it easier to set a bunch of configure
    # options at once.
    #
    def configure(&block)
      block_context = block.binding.receiver

      # If the block was defined in our own context, instance_exec is sufficient
      return instance_exec(&block) if equal?(block_context)

      # Copy the caller's instance variables in so that references like @filter
      # inside the block resolve to the caller's values, not ours.
      saved = swap_ivars_from(block_context)
      instance_exec(&block)
    ensure
      restore_ivars(block_context, saved) if defined?(saved) && saved
    end

    #
    # Gets or sets the behavior to process coverage results.
    #
    # By default, it will call SimpleCov.result.format!
    #
    # Configure with:
    #
    #     SimpleCov.at_exit do
    #       puts "Coverage done"
    #       SimpleCov.result.format!
    #     end
    #
    def at_exit(&block)
      @at_exit = block if block
      return @at_exit if @at_exit
      return proc {} unless active_session?

      @at_exit = proc { SimpleCov.result.format! }
    end

    # Whether SimpleCov has anything to do at exit: the Coverage module
    # is actively tracking, or a `@result` has already been assembled
    # (e.g. by `SimpleCov.collate`, which never starts Coverage). The
    # `defined?` guard avoids a NameError on the constant lookup when
    # Coverage was never required.
    def active_session?
      SimpleCov.result? || (defined?(Coverage) && Coverage.running?)
    end

    #
    # Get or set whether SimpleCov should hook `Process._fork` to attach
    # itself to subprocesses. Required when the suite uses parallel test
    # workers (e.g. Rails' `parallelize(workers:)`); without this, the
    # workers' coverage is dropped on the floor. Defaults to false.
    #
    #     SimpleCov.start do
    #       merge_subprocesses true
    #     end
    #
    def merge_subprocesses(value = nil)
      return @enable_for_subprocesses if defined?(@enable_for_subprocesses) && value.nil?

      @enable_for_subprocesses = value || false
    end

    # @api private
    # Predicate used by `start_tracking` to decide whether to install the
    # fork hook. Not part of the configuration DSL.
    def enabled_for_subprocesses?
      defined?(@enable_for_subprocesses) ? @enable_for_subprocesses : false
    end

    #
    # Get or set whether SimpleCov should auto-require the `parallel_tests`
    # gem when it sees `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` in the
    # environment. Defaults to auto-detect (nil): `SimpleCov.start` only
    # requires the gem when it's actually installed, and silently skips
    # otherwise.
    #
    # Set explicitly to opt in or out:
    #
    #     SimpleCov.start do
    #       parallel_tests true   # explicit opt-in; assume it's available
    #       parallel_tests false  # explicit opt-out; never auto-require
    #     end
    #
    # Useful when those env vars are set for reasons unrelated to the
    # parallel_tests gem (subprocess coordination, custom CI sharding,
    # etc.) and the auto-require's `LoadError` warning is unwanted. See
    # #1018.
    #
    def parallel_tests(value = :__no_arg__)
      return defined?(@parallel_tests) ? @parallel_tests : nil if value == :__no_arg__

      @parallel_tests = value
    end

    #
    # DEPRECATED: alias for `merge_subprocesses`. Same value, same behavior.
    #
    def enable_for_subprocesses(value = nil)
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.enable_for_subprocesses` is deprecated. " \
           "Replace with `SimpleCov.merge_subprocesses` (same value, same behavior)."
      return @enable_for_subprocesses if defined?(@enable_for_subprocesses) && value.nil?

      @enable_for_subprocesses = value || false
    end

    #
    # Gets or sets the behavior to start a new forked Process.
    #
    # By default, it will add " (Process #{pid})" to the command_name, and start SimpleCov in quiet mode
    #
    # Configure with:
    #
    #     SimpleCov.at_fork do |pid|
    #       SimpleCov.start do
    #         # This needs a unique name so it won't be ovewritten
    #         SimpleCov.command_name "#{SimpleCov.command_name} (subprocess: #{pid})"
    #         # be quiet — the parent process is in charge of using the regular formatter and checking coverage totals
    #         SimpleCov.print_errors false
    #         SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter
    #         SimpleCov.minimum_coverage 0
    #         # start
    #         SimpleCov.start
    #       end
    #     end
    #
    def at_fork(&block)
      @at_fork = block if block
      @at_fork ||= lambda { |pid|
        # This needs a unique name so it won't be ovewritten
        SimpleCov.command_name "#{SimpleCov.command_name} (subprocess: #{pid})"
        # be quiet, the parent process will be in charge of using the regular formatter and checking coverage totals
        SimpleCov.print_errors false
        SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter
        SimpleCov.minimum_coverage 0
        # start
        SimpleCov.start
      }
    end

    #
    # Returns the project name - currently assuming the last dirname in
    # the SimpleCov.root is this.
    #
    def project_name(new_name = nil)
      return @project_name if defined?(@project_name) && @project_name && new_name.nil?

      @project_name = new_name if new_name.is_a?(String)
      @project_name ||= File.basename(root).capitalize.tr("_", " ")
    end

    #
    # Get or set whether to merge results from multiple test suites
    # (test:units, test:functionals, cucumber, ...) into a single coverage
    # report. Defaults to true.
    #
    #     SimpleCov.start do
    #       merging false   # disable for one-shot runs
    #     end
    #
    def merging(use = nil)
      @use_merging = use unless use.nil?
      @use_merging = true unless defined?(@use_merging) && @use_merging == false
      @use_merging
    end

    #
    # DEPRECATED: alias for `merging`. Same value, same behavior.
    #
    def use_merging(use = nil)
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.use_merging` is deprecated. " \
           "Replace with `SimpleCov.merging` (same value, same behavior)."
      @use_merging = use unless use.nil?
      @use_merging = true unless defined?(@use_merging) && @use_merging == false
    end

    #
    # Defines the maximum age (in seconds) of a resultset to still be included in merged results.
    # i.e. If you run cucumber features, then later rake test, if the stored cucumber resultset is
    # more seconds ago than specified here, it won't be taken into account when merging (and is also
    # purged from the resultset cache)
    #
    # Of course, this only applies when merging is active (e.g. SimpleCov.use_merging is not false!)
    #
    # Default is 600 seconds (10 minutes)
    #
    # Configure with SimpleCov.merge_timeout(3600) # 1hr
    #
    def merge_timeout(seconds = nil)
      @merge_timeout = seconds if seconds.is_a?(Integer)
      @merge_timeout ||= 600
    end

    #
    # Defines the minimum overall coverage required for the testsuite to pass.
    # SimpleCov will return non-zero if the current coverage is below this threshold.
    #
    # Default is 0% (disabled)
    #
    def minimum_coverage(coverage = nil)
      return @minimum_coverage ||= {} unless coverage

      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)

      raise_on_invalid_coverage(coverage, "minimum_coverage")

      @minimum_coverage = coverage
    end

    def raise_on_invalid_coverage(coverage, coverage_setting)
      coverage.each_key { |criterion| raise_if_criterion_disabled(criterion) }
      coverage.each_value do |percent|
        minimum_possible_coverage_exceeded(coverage_setting) if percent && percent > 100
      end
    end

    #
    # Defines the maximum overall coverage allowed for the testsuite to pass.
    # SimpleCov will return non-zero if the current coverage exceeds this threshold.
    #
    # Most users only want a minimum, but a maximum is useful in two ways:
    # paired with `minimum_coverage` (or via `expected_coverage`) it pins
    # coverage to an exact value, so an unexpected jump up — typically a
    # sign that the threshold should be bumped — fails the build instead
    # of silently being absorbed. See https://github.com/simplecov-ruby/simplecov/issues/187.
    #
    # Default is unset (no upper bound).
    #
    def maximum_coverage(coverage = nil)
      return @maximum_coverage ||= {} unless coverage

      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)

      raise_on_invalid_coverage(coverage, "maximum_coverage")

      @maximum_coverage = coverage
    end

    #
    # Sets both `minimum_coverage` and `maximum_coverage` to the same value,
    # pinning the suite to an exact coverage figure. Useful for keeping
    # coverage from regressing AND from silently improving — when it does
    # improve, you want to know so you can ratchet the threshold up.
    #
    # Accepts the same shapes as `minimum_coverage`: a Numeric (applied to
    # the primary criterion) or a Hash of criteria to thresholds.
    #
    #     SimpleCov.expected_coverage 95.42
    #     SimpleCov.expected_coverage line: 100, branch: 95
    #
    # Tolerance: comparisons floor the actual coverage to two decimal
    # places before checking, so an actual of e.g. 95.4287 is treated as
    # 95.42 for both the minimum and maximum checks.
    #
    # See https://github.com/simplecov-ruby/simplecov/issues/187.
    #
    def expected_coverage(coverage = nil)
      return minimum_coverage if coverage.nil?

      minimum_coverage(coverage)
      maximum_coverage(coverage)
    end

    #
    # Defines the maximum coverage drop at once allowed for the testsuite to pass.
    # SimpleCov will return non-zero if the coverage decreases by more than this threshold.
    #
    # Default is 100% (disabled)
    #
    def maximum_coverage_drop(coverage_drop = nil)
      return @maximum_coverage_drop ||= {} unless coverage_drop

      coverage_drop = {primary_coverage => coverage_drop} if coverage_drop.is_a?(Numeric)

      raise_on_invalid_coverage(coverage_drop, "maximum_coverage_drop")

      @maximum_coverage_drop = coverage_drop
    end

    #
    # Defines the minimum coverage per file required for the testsuite to pass.
    # SimpleCov will return non-zero if the current coverage of the least covered file
    # is below this threshold. Default is 0% (disabled).
    #
    # Accepts a Numeric (global threshold on the primary criterion), a Symbol-keyed
    # Hash (per-criterion globals), or a Hash mixing Symbol keys with String / Regexp
    # keys to declare per-path overrides. For each file the effective threshold is
    # the Symbol-keyed defaults merged with any matching overrides — later overrides
    # win per criterion, overrides win over defaults. See the README and #575.
    #
    def minimum_coverage_by_file(coverage = nil)
      return @minimum_coverage_by_file ||= {} unless coverage

      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)

      defaults, overrides = partition_per_file_thresholds(coverage)

      raise_on_invalid_coverage(defaults, "minimum_coverage_by_file")
      overrides.each_value { |criteria| raise_on_invalid_coverage(criteria, "minimum_coverage_by_file") }

      @minimum_coverage_by_file = defaults
      @minimum_coverage_by_file_overrides = overrides
    end

    # Returns the per-path overrides set via `minimum_coverage_by_file`,
    # as an ordered Hash mapping each pattern (String or Regexp) to its
    # per-criterion thresholds Hash. Defaults to an empty Hash.
    def minimum_coverage_by_file_overrides
      @minimum_coverage_by_file_overrides ||= {}
    end

    #
    # Defines the minimum coverage per group required for the testsuite to pass.
    # SimpleCov will return non-zero if the current coverage of the least covered group
    # is below this threshold.
    #
    # Default is 0% (disabled)
    #
    def minimum_coverage_by_group(coverage = nil)
      return @minimum_coverage_by_group ||= {} unless coverage

      @minimum_coverage_by_group = coverage.dup.transform_values do |group_coverage|
        group_coverage = {primary_coverage => group_coverage} if group_coverage.is_a?(Numeric)

        raise_on_invalid_coverage(group_coverage, "minimum_coverage_by_group")

        group_coverage
      end
    end

    #
    # Refuses any coverage drop. That is, coverage is only allowed to increase.
    # SimpleCov will return non-zero if the coverage decreases.
    #
    def refuse_coverage_drop(*criteria)
      criteria = coverage_criteria if criteria.empty?

      maximum_coverage_drop(criteria.to_h { |c| [c, 0] })
    end

    #
    # Drop matching files from the coverage report. The inverse of `cover`.
    #
    # There are four ways to define a skip:
    #
    # * as a String that is matched (path-segment substring) against the
    #     project-relative path of each source file:
    #     SimpleCov.skip 'app/models' # drops everything under app/models
    # * as a Regexp matched against the same project-relative path:
    #     SimpleCov.skip %r{\Aconfig/}
    # * as a block that receives the SourceFile and returns truthy to drop:
    #     SimpleCov.skip do |sf|
    #       File.basename(sf.filename) == 'environment.rb'
    #     end
    # * as an Array of any of the above, dispatched element-by-element.
    #
    # Note on string semantics: `skip` uses the same path-segment substring
    # matcher as the legacy `add_filter` (so `skip 'lib'` matches `/lib/foo.rb`
    # but not `/library.rb`). This differs from `cover`'s string-as-glob
    # behavior. The split is preserved for ergonomic continuity with
    # `add_filter`; pass a Regexp if you need precise control.
    #
    def skip(filter_argument = nil, &)
      filters << parse_filter(filter_argument, &)
    end

    #
    # DEPRECATED: alias for `skip`. Same matcher grammar, identical behavior.
    #
    def add_filter(filter_argument = nil, &block)
      example = block ? "`SimpleCov.skip { ... }`" : "`SimpleCov.skip #{filter_argument.inspect}`"
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.add_filter` is deprecated. " \
           "Replace with `SimpleCov.skip` (same arguments, same behavior). Example: #{example}."
      skip(filter_argument, &block)
    end

    #
    # Remove any filters in the chain whose `filter_argument` equals the given
    # value. Useful for selectively dropping one of the defaults loaded by
    # `SimpleCov.start` (e.g. the hidden-files filter that drops paths starting
    # with `.`). Strings and Regexps compare by value; for filters added with a
    # block, the same Proc object must be passed back.
    #
    #     SimpleCov.remove_filter(/\A\..*/)     # drop the hidden-files default
    #     SimpleCov.remove_filter "/vendor/bundle/"
    #
    # Returns true when at least one filter was removed, false otherwise.
    #
    def remove_filter(filter_argument) # rubocop:disable Naming/PredicateMethod
      before = filters.size
      filters.reject! { |filter| filter.respond_to?(:filter_argument) && filter.filter_argument == filter_argument }
      filters.size != before
    end

    #
    # Remove every filter from the chain, including the defaults installed by
    # `SimpleCov.start`. Use this when you want a clean slate before adding
    # your own filters; for selective removal, prefer `remove_filter`.
    #
    def clear_filters
      @filters = []
    end

    #
    # Define a display group for files. Same matcher grammar as `skip`,
    # but instead of dropping the matching files it bins them under
    # `group_name` for the formatter. Files matched by no group fall
    # into the implicit "Ungrouped" bucket.
    #
    def group(group_name, filter_argument = nil, &)
      groups[group_name] = parse_filter(filter_argument, &)
    end

    #
    # DEPRECATED: alias for `group`. Same arguments, same behavior.
    #
    def add_group(group_name, filter_argument = nil, &block)
      example = if block
                  "`SimpleCov.group #{group_name.inspect} { ... }`"
                else
                  "`SimpleCov.group #{group_name.inspect}, #{filter_argument.inspect}`"
                end
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.add_group` is deprecated. " \
           "Replace with `SimpleCov.group` (same arguments, same behavior). Example: #{example}."
      group(group_name, filter_argument, &block)
    end

    #
    # Drop every filter previously installed (defaults plus anything
    # earlier in this block) so subsequent `skip` calls start from a
    # clean slate. Equivalent to `clear_filters`, but named for the
    # common case: opting out of the default `vendor/bundle/`,
    # hidden-files, root-boundary, and test-framework filters that
    # `SimpleCov.start` installs before the user's block runs.
    #
    # Order matters — `no_default_skips` wipes anything that has been
    # registered up to that point, so call it before your own `skip`
    # invocations.
    #
    def no_default_skips
      clear_filters
    end

    SUPPORTED_COVERAGE_CRITERIA = %i[line branch method oneshot_line].freeze
    DEFAULT_COVERAGE_CRITERION = :line
    ONESHOT_LINE_COVERAGE_CRITERION = :oneshot_line
    #
    # Define which coverage criterion should be evaluated.
    #
    # Possible coverage criteria:
    # * :line - coverage based on lines aka has this line been executed?
    # * :branch - coverage based on branches aka has this branch (think conditions) been executed?
    #
    # If not set the default is `:line`
    #
    # @param [Symbol] criterion
    #
    def coverage_criterion(criterion = nil)
      return @coverage_criterion ||= primary_coverage unless criterion

      raise_if_criterion_unsupported(criterion)

      @coverage_criterion = criterion
    end

    # Enable one or more coverage criteria. Accepts a single Symbol
    # (`enable_coverage :branch`) or several at once
    # (`enable_coverage :branch, :method`).
    #
    # `:eval` is accepted as a shorthand for the standalone eval-coverage
    # toggle. Note that `:eval` is not a regular coverage criterion — it
    # opts the Coverage runtime into instrumenting `eval`'d code rather
    # than enabling a third measurement type — but folding it into this
    # method lets one call configure everything you want to measure.
    def enable_coverage(*criteria)
      criteria.each do |criterion|
        if criterion == :eval
          enable_eval_coverage
        else
          raise_if_criterion_unsupported(criterion)

          # :oneshot_lines can not be combined with :lines
          coverage_criteria.delete(DEFAULT_COVERAGE_CRITERION) if criterion == ONESHOT_LINE_COVERAGE_CRITERION

          coverage_criteria << criterion
        end
      end
    end

    # Remove `criterion` from the set of enabled coverage criteria. The
    # default set is `Set[:line]`; calling `disable_coverage :line`
    # (after `enable_coverage :branch`, say) makes a branch-only run
    # possible. If the disabled criterion was the primary, the next
    # call to `primary_coverage` falls back to the first remaining
    # member of `coverage_criteria`.
    #
    # Disabling every criterion raises at `start_tracking`, not here,
    # so configuration files that toggle criteria in arbitrary order
    # don't have to worry about transient empty states.
    def disable_coverage(criterion)
      raise_if_criterion_unsupported(criterion)
      coverage_criteria.delete(criterion)
      @primary_coverage = nil if @primary_coverage == criterion
    end

    # Branch coverage entries that should not count toward the report when
    # they appear in the raw `Coverage.result`. Supported tokens:
    #
    # * `:implicit_else` (see #1033) drops synthetic `else` arms that
    #   Ruby's Coverage library reports for constructs without a literal
    #   `else` keyword (`case/in` without `else`, `case/when` without
    #   `else`, `||=`, `&&=`, `if` without `else`). They show up as
    #   "missed" branches and depress the branch-coverage percentage
    #   even though the source has no corresponding code to exercise.
    # * `:eval_generated` (see #1046) drops branches whose source range
    #   does not correspond to a real conditional in the file. Ruby's
    #   Coverage attributes `module_eval(body, __FILE__, __LINE__)` to
    #   the calling file/line, so macros like Rails' `delegate` inject
    #   "missed" entries into otherwise clean source files when
    #   `enable_coverage :eval` is on. Detection uses Prism to walk the
    #   real source and treats any Coverage entry whose start_line does
    #   not coincide with a real branch construct (`if`, `unless`,
    #   ternary, `case/when`, `case/in`, `while`, `until`) as
    #   eval-generated.
    #
    # Variadic. Pass one or more tokens. Multiple calls union:
    #
    #     SimpleCov.start do
    #       enable_coverage :branch
    #       ignore_branches :implicit_else, :eval_generated
    #     end
    #
    # The setting is recorded regardless of whether branch coverage is
    # enabled at call time, so call order doesn't matter.
    # `ignore_branches :implicit_else` before `enable_coverage :branch`
    # (or vice versa) both apply the filter. If branch coverage is never
    # enabled, the stored setting has nothing to filter and produces no
    # observable change in the report. Unknown tokens raise
    # `SimpleCov::ConfigurationError` immediately to catch typos.
    IGNORABLE_BRANCH_TYPES = %i[implicit_else eval_generated].freeze

    def ignore_branches(*types)
      types.each { |type| raise_if_branch_type_unsupported(type) }
      ignored_branches.concat(types).uniq!
      ignored_branches
    end

    def ignored_branches
      @ignored_branches ||= []
    end

    def ignored_branch?(type)
      ignored_branches.include?(type)
    end

    # Method coverage entries that should not count toward the report
    # when they appear in the raw `Coverage.result`. The only currently
    # supported token is `:eval_generated` (see #1046), which drops
    # method entries whose source position does not correspond to a
    # real `def` keyword in the file. Macros that synthesize methods
    # via `module_eval` / `class_eval` (Rails' `delegate`, ActiveRecord
    # associations, `attr_accessor`-style helpers) inject "missed"
    # method entries when `enable_coverage :eval` is on. Detection uses
    # Prism to walk the real source and treat any Coverage method
    # entry whose start_line does not match a real `def` as
    # eval-generated.
    #
    # Variadic. Same lifecycle as `ignore_branches`: setting is recorded
    # regardless of whether method coverage is enabled, applies once
    # method coverage is enabled, no observable effect if it never is.
    # Unknown tokens raise `SimpleCov::ConfigurationError`.
    IGNORABLE_METHOD_TYPES = %i[eval_generated].freeze

    def ignore_methods(*types)
      types.each { |type| raise_if_method_type_unsupported(type) }
      ignored_methods.concat(types).uniq!
      ignored_methods
    end

    def ignored_methods
      @ignored_methods ||= []
    end

    def ignored_method?(type)
      ignored_methods.include?(type)
    end

    def primary_coverage(criterion = nil)
      if criterion.nil?
        @primary_coverage ||= default_primary_coverage
      else
        raise_if_criterion_disabled(criterion)
        @primary_coverage = criterion
      end
    end

    def coverage_criteria
      @coverage_criteria ||= Set[DEFAULT_COVERAGE_CRITERION]
    end

    def coverage_criterion_enabled?(criterion)
      coverage_criteria.member?(criterion)
    end

    # Reset the criteria back to the lazy default (`Set[:line]`). The
    # next read of `coverage_criteria` rebuilds the default through the
    # `||=` in the getter. To genuinely empty the set, call
    # `disable_coverage` on each enabled criterion instead — that's the
    # path `validate_coverage_criteria!` is meant to flag.
    def clear_coverage_criteria
      @coverage_criteria = nil
      @primary_coverage = nil
    end

    # @api private
    #
    # Called from `SimpleCov.start_tracking` to fail fast when the user
    # has disabled every coverage criterion. Without at least one,
    # `Coverage.start` would receive no arguments and the runtime would
    # silently produce no data.
    def validate_coverage_criteria!
      return unless coverage_criteria.empty?

      raise SimpleCov::ConfigurationError,
            "At least one coverage criterion must be enabled. " \
            "Re-enable one with `enable_coverage :line`, `:branch`, or `:method`."
    end

    def branch_coverage?
      branch_coverage_supported? && coverage_criterion_enabled?(:branch)
    end

    def branch_coverage_supported?
      RUBY_ENGINE != "jruby"
    end

    def method_coverage?
      method_coverage_supported? && coverage_criterion_enabled?(:method)
    end

    def method_coverage_supported?
      RUBY_ENGINE != "jruby"
    end

    def coverage_for_eval_supported?
      require "coverage"
      defined?(Coverage.supported?) && Coverage.supported?(:eval)
    end

    def coverage_for_eval_enabled?
      @coverage_for_eval_enabled ||= false
    end

    #
    # DEPRECATED: prefer `enable_coverage :eval`, which folds the eval
    # toggle into the same call that enables `:line` / `:branch` / etc.
    #
    def enable_coverage_for_eval
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.enable_coverage_for_eval` is deprecated. " \
           "Replace with `SimpleCov.enable_coverage :eval`."
      enable_eval_coverage
    end

  private

    # Shared implementation backing both `enable_coverage :eval` and the
    # deprecated `enable_coverage_for_eval`. Sets the flag when the runtime
    # supports eval coverage; warns and leaves the flag false otherwise.
    def enable_eval_coverage
      if coverage_for_eval_supported?
        @coverage_for_eval_enabled = true
      else
        warn "Coverage for eval is not available; Use Ruby 3.2.0 or later"
      end
    end

    # If `:line` is enabled, it's the default primary — keeps the
    # historical behavior for every existing project. If the user has
    # disabled `:line`, fall back to whichever criterion they actually
    # enabled (in insertion order). Returning `:line` even when it's
    # disabled would propagate broken state into the numeric form of
    # `minimum_coverage 90`.
    def default_primary_coverage
      return DEFAULT_COVERAGE_CRITERION if coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION)

      coverage_criteria.first
    end

    def raise_if_criterion_disabled(criterion)
      raise_if_criterion_unsupported(criterion)
      return if coverage_criterion_enabled?(criterion)

      raise SimpleCov::ConfigurationError,
            "Coverage criterion #{criterion}, is disabled! " \
            "Please enable it first through enable_coverage #{criterion} (if supported)"
    end

    def raise_if_criterion_unsupported(criterion)
      return if SUPPORTED_COVERAGE_CRITERIA.member?(criterion)

      raise SimpleCov::ConfigurationError,
            "Unsupported coverage criterion #{criterion}, supported values are #{SUPPORTED_COVERAGE_CRITERIA}"
    end

    def raise_if_branch_type_unsupported(type)
      return if IGNORABLE_BRANCH_TYPES.member?(type)

      raise SimpleCov::ConfigurationError,
            "Unsupported branch type #{type.inspect} for `ignore_branches`. " \
            "Supported values are #{IGNORABLE_BRANCH_TYPES.inspect}"
    end

    def raise_if_method_type_unsupported(type)
      return if IGNORABLE_METHOD_TYPES.member?(type)

      raise SimpleCov::ConfigurationError,
            "Unsupported method type #{type.inspect} for `ignore_methods`. " \
            "Supported values are #{IGNORABLE_METHOD_TYPES.inspect}"
    end

    def minimum_possible_coverage_exceeded(coverage_option)
      warn "The coverage you set for #{coverage_option} is greater than 100%"
    end

    # Split a `minimum_coverage_by_file` argument into Symbol-keyed criterion
    # defaults and String/Regexp-keyed per-path overrides; normalize Numeric
    # override values to `{primary_coverage => N}` so downstream code only
    # has one shape to handle.
    def partition_per_file_thresholds(coverage)
      coverage.each_key { |key| validate_per_file_key(key) }
      defaults, raw = coverage.partition { |key, _| key.is_a?(Symbol) }.map(&:to_h)
      overrides = raw.transform_values { |value| value.is_a?(Numeric) ? {primary_coverage => value} : value }
      [defaults, overrides]
    end

    def validate_per_file_key(key)
      return if key.is_a?(Symbol) || key.is_a?(String) || key.is_a?(Regexp)

      raise SimpleCov::ConfigurationError,
            "minimum_coverage_by_file keys must be Symbol (criterion), String, or Regexp; got #{key.inspect}"
    end

    # Copy instance variables from block_context into self, saving any of ours
    # that would be clobbered. Returns the saved values for later restoration.
    def swap_ivars_from(block_context)
      saved = {}
      our_ivars = instance_variables
      block_context.instance_variables.each do |ivar|
        saved[ivar] = instance_variable_get(ivar) if our_ivars.include?(ivar)
        instance_variable_set(ivar, block_context.instance_variable_get(ivar))
      end
      saved
    end

    # Copy instance variables back to block_context and restore our saved values.
    def restore_ivars(block_context, saved)
      block_context.instance_variables.each do |ivar|
        block_context.instance_variable_set(ivar, instance_variable_get(ivar))
      end
      saved.each { |ivar, value| instance_variable_set(ivar, value) }
    end

    #
    # The actual filter processor. Not meant for direct use
    #
    def parse_filter(filter_argument = nil, &filter_proc)
      filter = filter_argument || filter_proc

      raise ArgumentError, "Please specify either a filter or a block to filter with" unless filter

      SimpleCov::Filter.build_filter(filter)
    end

    # Build a filter for a `cover` argument. Strings are treated as
    # globs (not substrings — that's `skip`/`add_filter`'s semantics),
    # which matches the way `track_files` interpreted its string argument
    # and reflects the "this is the set of files I want reported"
    # mental model behind `cover`.
    def build_cover_filter(arg)
      case arg
      when String            then SimpleCov::GlobFilter.new(arg)
      when Regexp            then SimpleCov::RegexFilter.new(arg)
      when Proc              then SimpleCov::BlockFilter.new(arg)
      when SimpleCov::Filter then arg
      when Array             then SimpleCov::ArrayFilter.new(arg.map { |a| build_cover_filter(a) })
      else raise SimpleCov::ConfigurationError, "Unsupported `cover` argument #{arg.inspect}; " \
                                                "expected a String glob, Regexp, Proc, " \
                                                "SimpleCov::Filter, or Array of those."
      end
    end

    # Walk a list of cover filters and return the string globs they hold,
    # descending into `ArrayFilter` wrappers built by `cover(["a", "b"])`.
    def collect_cover_globs(filter_list)
      filter_list.flat_map do |filter|
        case filter
        when SimpleCov::GlobFilter  then filter.filter_argument
        when SimpleCov::ArrayFilter then collect_cover_globs(filter.filter_argument)
        else []
        end
      end
    end
  end
end
