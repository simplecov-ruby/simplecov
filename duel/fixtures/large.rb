# frozen_string_literal: true

require "fileutils"

module SimpleCov
  module Configuration
    def root(root = nil)
      return @root if instance_variable_defined?(:@root) && root.nil?

      self.root = root
      @root
    end

    # nil means the working directory, the default the reader would have derived.
    def root=(root)
      @coverage_path = nil unless @coverage_path_explicit # invalidate cache
      @root = File.expand_path(root || Dir.getwd)
    end

    def coverage_dir(dir = nil)
      return @coverage_dir if instance_variable_defined?(:@coverage_dir) && dir.nil?

      self.coverage_dir = dir
      @coverage_dir
    end

    # nil means the default 'coverage', recorded as a derivation rather than a
    # choice.
    def coverage_dir=(dir)
      @coverage_path = nil unless @coverage_path_explicit # invalidate cache
      @coverage_dir_explicit = true unless dir.nil?
      @coverage_dir = dir || "coverage"
    end

    #
    # Defaults to `SimpleCov.root` + `SimpleCov.coverage_dir`, but callers can
    # override with an arbitrary absolute path, handy for out-of-tree build
    # directories (#716).
    #
    # Reading is pure: the directory is only created when a path is explicitly
    # assigned. The codepaths that write into it ensure existence themselves,
    # so read-only CLI subcommands that interpolate the path into status text
    # don't materialize a stray `coverage/` directory.
    #
    def coverage_path(path = nil)
      self.coverage_path = path if path

      @coverage_path ||= File.expand_path(coverage_dir, root)
    end

    # Assigning is the signal the caller intends to write there, so the
    # directory is created.
    def coverage_path=(path)
      expanded = File.expand_path(path)
      @coverage_path = expanded
      @coverage_path_explicit = true
      FileUtils.mkdir_p expanded
    end

    #
    # The name of the command (a.k.a. Test Suite) currently running. Used for
    # result merging and caching. Auto-detected.
    #
    def command_name(name = nil)
      self.command_name = name unless name.nil?
      @command_name ||= CommandGuesser.guess
    end

    def command_name=(name)
      @command_name = name
    end

    def profiles
      @profiles ||= Profiles.new
    end

    #
    # Configure covtool in a block instead of prepending SimpleCov to each
    # config method. Parameterized blocks retain their caller context and
    # receive this configuration target explicitly.
    #
    def configure(&block)
      raise ArgumentError, "configuration block required" unless block

      if block.parameters.empty?
        instance_exec(&(_ = block))
      else
        yield self
      end
      self
    end

    def at_exit(&block)
      @at_exit = block if block
      configured = @at_exit
      return configured if configured
      return -> {} unless active_session?

      @at_exit = lambda do
        result = SimpleCov.result
        result.format! if result && SimpleCov.merge_finalization_owner?
      end
    end

    # The Coverage module is actively tracking, or a `@result` has already been
    # assembled (`SimpleCov.collate` never starts Coverage).
    def active_session?
      !!SimpleCov.result? || coverage_running?
    end

    # A configuration loaded on its own may have no Coverage to ask, which is
    # not something a suite that measures coverage can be.
    def coverage_running?
      defined?(Coverage) ? Coverage.running? : false
    end

    def at_fork(&block)
      @at_fork = block if block
      @at_fork ||= lambda { |_pid|
        # Needs a name that's unique per worker within a run yet identical across
        # runs. Built from SimpleCov's stable fork serial rather than the OS pid:
        # with the pid, every run produced uniquely-named results that never
        # overwrote the previous run's, so they piled up in .resultset.json
        # until merge_timeout and the merged report's file set drifted from run
        # to run (#1171).
        SimpleCov.command_name "#{SimpleCov.command_name} (subprocess: #{SimpleCov.subprocess_serial})"
        SimpleCov.print_errors false
        SimpleCov.formatter Formatter::SimpleFormatter
        SimpleCov.minimum_coverage 0
        SimpleCov.start
      }
    end

    # Only a String renames, and a name already chosen survives anything else.
    def project_name(new_name = nil)
      @project_name = new_name if new_name.is_a?(String)
      @project_name ||= File.basename(root).capitalize.tr("_", " ")
    end
  end
end

require_relative "configuration/coverage"
require_relative "configuration/coverage_criteria"
require_relative "configuration/eval_coverage"
require_relative "configuration/filters"
require_relative "configuration/groups"
require_relative "configuration/formatting"
require_relative "configuration/ignored_entries"
require_relative "configuration/merging"
require_relative "configuration/test_tracking"
require_relative "configuration/thresholds"
require_relative "configuration/baseline"
require_relative "configuration/deprecations"
require_relative "configuration/history"
require_relative "configuration/missed_caps"
require_relative "configuration/production"
require_relative "configuration/view_coverage"
# frozen_string_literal: true

module SimpleCov
  module Configuration
    # The baseline's path, relative to `SimpleCov.root`; an absolute path is
    # honored as given. The file's presence is the opt-in: generate it with
    # `covtool ratchet`, check it in, and the exit check holds every listed
    # file to its own floor (#1268).
    def baseline_file(path = nil)
      return @baseline_file ||= Baseline::DEFAULT_FILENAME unless path

      self.baseline_file = path
      _ = @baseline_file
    end

    def baseline_file=(path)
      @baseline_file = path
    end

    # Memoized per resolved path so the exit check and the JSON formatter's
    # errors section read the file once, while a `baseline_file` or `root` change
    # between reads is still picked up.
    def baseline
      resolved = File.expand_path(baseline_file, root)
      return @baseline if @baseline_path.eql?(resolved)

      @baseline_path = resolved
      @baseline = Baseline.read_if_exists(resolved)
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    SUPPORTED_COVERAGE_CRITERIA = %i[line branch method oneshot_line].freeze
    DEFAULT_COVERAGE_CRITERION = :line
    ONESHOT_LINE_COVERAGE_CRITERION = :oneshot_line
    LINE_COVERAGE_ALTERNATIVES = {line: :oneshot_line, oneshot_line: :line}.freeze #: line_coverage_alternatives
    private_constant :LINE_COVERAGE_ALTERNATIVES

    def enable_coverage(*criteria)
      criteria.each do |criterion|
        criterion.equal?(:eval) ? enable_eval_coverage : add_coverage_criterion(_ = criterion)
      end
    end

    # Disabling every criterion raises at `start_tracking`, not here, so config
    # files that toggle criteria in arbitrary order don't have to worry about
    # transient empty states.
    def disable_coverage(criterion)
      return disable_eval_coverage if criterion.equal?(:eval)

      raise_if_criterion_unsupported(_ = criterion)
      coverage_criteria.delete(_ = criterion)
      @primary_coverage = nil if @primary_coverage.equal?(criterion)
    end

    def primary_coverage(criterion = nil)
      if criterion.nil?
        @primary_coverage ||= default_primary_coverage
      else
        self.primary_coverage = criterion
      end
    end

    def primary_coverage=(criterion)
      raise_if_criterion_disabled(criterion)
      @primary_coverage = criterion
    end

    def coverage_criteria
      @coverage_criteria ||= Set[DEFAULT_COVERAGE_CRITERION]
    end

    def coverage_criterion_enabled?(criterion)
      coverage_criteria.member?(criterion)
    end

    def clear_coverage_criteria
      @coverage_criteria = nil
      @primary_coverage = nil
    end

    def validate_coverage_criteria!
      return unless coverage_criteria.empty?

      raise ConfigurationError,
        "At least one coverage criterion must be enabled. " \
        "Re-enable one with `enable_coverage :line`, `:branch`, or `:method`."
    end

    # Whether this run produces line data at all. The oneshot variant counts:
    # `ResultAdapter` turns its executed-line list back into a line array. A
    # branch-only or method-only run produces none, and `Coverage.result`
    # entries for the files it loaded carry no `"lines"` key.
    def line_coverage?
      coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION) ||
        coverage_criterion_enabled?(ONESHOT_LINE_COVERAGE_CRITERION)
    end

    def branch_coverage?
      branch_coverage_supported? && coverage_criterion_enabled?(:branch)
    end

    def branch_coverage_supported?
      coverage_criterion_supported?(:branches)
    end

    def method_coverage?
      method_coverage_supported? && coverage_criterion_enabled?(:method)
    end

    def method_coverage_supported?
      coverage_criterion_supported?(:methods)
    end

    def coverage_criterion_supported?(criterion)
      load_coverage
      Coverage.supported?(criterion)
    end

    # Loading `covtool/configuration` on its own leaves Coverage undefined, and
    # this question is asked at configuration time.
    def load_coverage
      require "coverage"
    end

    private

    def add_coverage_criterion(criterion)
      raise_if_criterion_unsupported(criterion)
      incompatible = LINE_COVERAGE_ALTERNATIVES[criterion]
      disable_coverage(incompatible) if incompatible
      coverage_criteria << criterion
    end

    # Answering `:line` even when it is disabled would propagate broken state
    # into `minimum_coverage 90`, so fall back to whichever criterion the user
    # actually enabled, in insertion order.
    def default_primary_coverage
      return DEFAULT_COVERAGE_CRITERION if coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION)

      _ = coverage_criteria.first
    end

    def raise_if_criterion_disabled(criterion)
      if criterion.equal?(:eval)
        raise ConfigurationError,
          "Coverage criterion :eval only toggles measuring eval'd code; " \
          "it cannot carry thresholds or serve as the primary criterion"
      end

      raise_if_criterion_unsupported(criterion)
      return if coverage_criterion_enabled?(criterion)

      raise ConfigurationError,
        "Coverage criterion #{criterion}, is disabled! " \
        "Please enable it first through enable_coverage #{criterion} (if supported)"
    end

    def raise_if_criterion_unsupported(criterion)
      return if SUPPORTED_COVERAGE_CRITERIA.member?(criterion)

      raise ConfigurationError,
        "Unsupported coverage criterion #{criterion}, supported values are #{SUPPORTED_COVERAGE_CRITERIA}"
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    COVERAGE_THRESHOLD_OPTIONS = %i[minimum maximum exact maximum_drop ignore minimum_per_file
      maximum_missed maximum_missed_per_file].freeze

    def coverage(criterion, primary: false, enabled: true, oneshot: false, **thresholds, &block)
      criterion = enable_coverage_criterion(criterion, enabled: enabled, oneshot: oneshot)
      # The cast admits :eval, which primary_coverage rejects at runtime.
      primary_coverage(_ = criterion) if primary

      configurator = CoverageCriterion.new(self, criterion)
      apply_threshold_options(configurator, thresholds)
      configurator.instance_eval(&block) if block

      criterion
    end

    private

    def apply_threshold_options(configurator, options)
      options.each do |verb, value|
        unless COVERAGE_THRESHOLD_OPTIONS.include?(verb)
          raise ConfigurationError,
            "Unknown `coverage` option #{verb.inspect}. " \
            "Supported options are #{COVERAGE_THRESHOLD_OPTIONS.inspect}."
        end

        configurator.public_send(verb, value)
      end
    end

    def enable_coverage_criterion(criterion, enabled:, oneshot:)
      criterion = resolve_criterion_variant(criterion, oneshot)
      enabled ? enable_coverage(criterion) : disable_coverage(criterion)
      criterion
    end

    def resolve_criterion_variant(criterion, oneshot)
      return criterion unless oneshot

      raise ConfigurationError, "`oneshot: true` is only valid for `coverage :line`" unless criterion.equal?(:line)

      ONESHOT_LINE_COVERAGE_CRITERION
    end

    # @api private
    def store_overall_threshold(setting, criterion, percent)
      raise_on_invalid_coverage({criterion => percent}, setting)
      public_send(setting)[criterion] = percent
    end

    def store_missed_cap(setting, criterion, count)
      raise_if_criterion_disabled(criterion)
      raise_on_invalid_missed_cap(count, setting)
      public_send(setting)[criterion] = count
    end

    def store_maximum_missed_per_file(criterion, count, target)
      raise_if_criterion_disabled(criterion)
      raise_on_invalid_missed_cap(count, "maximum_missed_per_file")
      return maximum_missed_per_file[criterion] = count if target.nil?

      unless target.is_a?(String) || target.is_a?(Regexp)
        raise ConfigurationError, "`only:` must be a String path or Regexp, got #{target.inspect}"
      end

      (maximum_missed_per_file_overrides[target] ||= {})[criterion] = count
    end

    def store_minimum_per_file(criterion, percent, target)
      raise_on_invalid_coverage({criterion => percent}, "minimum_coverage_by_file")
      return minimum_coverage_by_file[criterion] = percent if target.nil?

      unless target.is_a?(String) || target.is_a?(Regexp)
        raise ConfigurationError, "`only:` must be a String path or Regexp, got #{target.inspect}"
      end

      (minimum_coverage_by_file_overrides[target] ||= {})[criterion] = percent
    end

    def store_minimum_per_group(criterion, percent, group_name)
      raise_on_invalid_coverage({criterion => percent}, "minimum_coverage_by_group")
      # Normalized like `group` does, so `per: group(:Models)` finds the group
      # defined as `group "Models"` at check time.
      (minimum_coverage_by_group[GroupNames.normalize(group_name)] ||= {})[criterion] = percent
    end

    #
    # Receiver for a `coverage <criterion> do ... end` block.
    #
    class CoverageCriterion
      def initialize(config, criterion)
        @config = config
        @criterion = criterion
      end

      def minimum(percent, per: nil)
        case per
        when nil then @config.__send__(:store_overall_threshold, :minimum_coverage, @criterion, percent)
        when :file then @config.__send__(:store_minimum_per_file, @criterion, percent, nil)
        when String, Regexp then @config.__send__(:store_minimum_per_file, @criterion, percent, per)
        when GroupTarget then @config.__send__(:store_minimum_per_group, @criterion, percent, per.name)
        else raise_invalid_per(per)
        end
      end

      def maximum(percent)
        @config.__send__(:store_overall_threshold, :maximum_coverage, @criterion, percent)
      end

      def exact(percent)
        minimum(percent)
        maximum(percent)
      end

      def maximum_drop(percent)
        @config.__send__(:store_overall_threshold, :maximum_coverage_drop, @criterion, percent)
      end

      def maximum_missed(count, per: nil)
        case per
        when nil then @config.__send__(:store_missed_cap, :maximum_missed, @criterion, count)
        when :file then @config.__send__(:store_maximum_missed_per_file, @criterion, count, nil)
        when String, Regexp then @config.__send__(:store_maximum_missed_per_file, @criterion, count, per)
        when GroupTarget
          raise ConfigurationError,
            "maximum_missed does not support `per: group(...)` yet; see docs/Roadmap.md"
        else raise_invalid_per(per)
        end
      end

      def group(name)
        GroupTarget.new(name: name)
      end

      # The flatten serves the one-liner keyword form, whose value arrives as a
      # single argument (`ignore: %i[implicit_else]`).
      def ignore(*types)
        case @criterion
        when :branch then @config.__send__(:store_ignored_branches, types.flatten)
        when :method then @config.__send__(:store_ignored_methods, types.flatten)
        else
          raise ConfigurationError,
            "`ignore` is supported for `coverage :branch` and `coverage :method`, not #{@criterion.inspect}"
        end
      end

      def minimum_per_file(percent, only: nil)
        Deprecation.warn("`minimum_per_file` is deprecated. " \
                         "Replace with `minimum #{percent}, per: #{(only || :file).inspect}`.")
        @config.__send__(:store_minimum_per_file, @criterion, percent, only)
      end

      def minimum_per_group(percent, only:)
        Deprecation.warn("`minimum_per_group` is deprecated. " \
                         "Replace with `minimum #{percent}, per: group(#{only.inspect})`.")
        @config.__send__(:store_minimum_per_group, @criterion, percent, only)
      end

      def maximum_missed_per_file(count, only: nil)
        Deprecation.warn("`maximum_missed_per_file` is deprecated. " \
                         "Replace with `maximum_missed #{count}, per: #{(only || :file).inspect}`.")
        @config.__send__(:store_maximum_missed_per_file, @criterion, count, only)
      end

      def primary
        # @criterion is Symbol-wide because this receiver is also built for
        # :eval; primary_coverage validates at runtime.
        @config.primary_coverage(_ = @criterion)
      end

      GroupTarget = Data.define(:name)

      private

      def raise_invalid_per(per)
        raise ConfigurationError,
          "`per:` must be :file, a String path, a Regexp, or group(\"Name\"), got #{per.inspect}"
      end
    end
  end
end
# frozen_string_literal: true

require_relative "../deprecation"

module SimpleCov
  module Configuration
    DEPRECATION_MODES = Deprecation::MODES

    # The configuration DSL migrates by warn-and-delegate, which means a project
    # can run on deprecated spellings indefinitely without noticing.
    # `deprecations :raise` turns every deprecated API into a ConfigurationError,
    # so a project that has migrated can guard in CI against old spellings
    # creeping back. There is deliberately no silencing mode: a deprecation you
    # cannot see is a migration you never make.
    def deprecations(mode = nil)
      return Deprecation.mode unless mode

      Deprecation.mode = mode
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    # The standalone eval-coverage toggle, kept apart from the criteria-set logic
    # in `coverage_criteria.rb` because `:eval` is a boolean toggle, never a
    # member of the enabled-criteria set.
    def coverage_for_eval_supported?
      coverage_criterion_supported?(:eval)
    end

    def coverage_for_eval_enabled?
      @coverage_for_eval_enabled ||= false
    end

    def enable_coverage_for_eval
      Deprecation.warn("`SimpleCov.enable_coverage_for_eval` is deprecated. " \
                       "Replace with `SimpleCov.enable_coverage :eval`.")
      enable_eval_coverage
    end

    private

    def enable_eval_coverage
      if coverage_for_eval_supported?
        @coverage_for_eval_enabled = true
      else
        warn "Coverage for eval is not available on this Ruby"
      end
    end

    # No support check needed: off is a safe state on every Ruby.
    def disable_eval_coverage
      @coverage_for_eval_enabled = false
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    attr_writer :filters

    #
    # Restrict the universe of files in the coverage report to those matching
    # one or more globs, regexps, or block predicates. Multiple calls union;
    # when any `cover` matcher is configured the report drops every file that
    # doesn't match at least one of them.
    #
    # Strings are interpreted as shell globs, not substring matches, a
    # deliberate departure from the legacy `add_filter` semantics.
    #
    # A string glob is also expanded on disk, so files that exist but were
    # never required during the run still appear in the report at 0%. This is
    # the "include unloaded files" half of the legacy `track_files` behavior.
    #
    def cover(*args, &block)
      args.each { |arg| cover_filters << build_cover_filter(arg) }
      cover_filters << BlockFilter.new(block) if block
      cover_filters
    end

    def cover_filters
      @cover_filters ||= []
    end

    # The string globs passed to `cover`, used by the disk-discovery pass in
    # `SimpleCov.tracked_file_paths` so files matching a `cover` glob appear in
    # the report even when they were never required during the suite.
    def cover_globs
      collect_cover_globs(cover_filters)
    end

    def track_files(glob)
      Deprecation.warn("`SimpleCov.track_files` is deprecated. " \
                       "#{track_files_replacement_hint(glob)}")
      @tracked_files = glob
    end

    # `track_files(nil)` is the documented way to clear a previously-set glob,
    # but `cover(nil)` raises `ConfigurationError`, so don't point users at it.
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

    # Nil until `cover` names a glob: an unset ivar reads as nil, so the absence
    # needs no guard of its own.
    def tracked_files
      @tracked_files
    end

    def filters
      @filters ||= []
    end

    #
    # Drop matching files from the coverage report. The inverse of `cover`.
    # Accepts a String (path-segment substring), Regexp, block predicate, or
    # Array of any of those.
    #
    def skip(filter_argument = nil, &)
      filters << parse_filter(filter_argument, &)
    end

    def add_filter(filter_argument = nil, &block)
      example = block ? "`SimpleCov.skip { ... }`" : "`SimpleCov.skip #{filter_argument.inspect}`"
      Deprecation.warn("`SimpleCov.add_filter` is deprecated. " \
                       "Replace with `SimpleCov.skip` (same arguments, same behavior). Example: #{example}.")
      skip(filter_argument, &block)
    end

    # `reject!` answers nil when it rejected nothing, which is the whole of
    # "was anything removed".
    def remove_filter(filter_argument)
      rejected = filters.reject! do |filter|
        filter.respond_to?(:filter_argument) && filter.filter_argument.eql?(filter_argument)
      end
      !rejected.nil?
    end

    def clear_filters
      @filters = []
    end

    # Order matters: call this before your own `skip` invocations.
    def no_default_skips
      clear_filters
    end

    private

    def parse_filter(filter_argument = nil, &filter_proc)
      filter = filter_argument || filter_proc

      raise ArgumentError, "Please specify either a filter or a block to filter with" unless filter

      Filter.build_filter(filter)
    end

    # Strings are treated as globs, not substrings (that's `skip`'s
    # semantics); everything else dispatches exactly like `add_filter`.
    def build_cover_filter(arg)
      Filter.build_filter(arg, string_filter: GlobFilter)
    rescue ConfigurationError
      raise ConfigurationError, "Unsupported `cover` argument #{arg.inspect}; " \
                                "expected a String glob, Regexp, Proc, " \
                                "SimpleCov::Filter, or Array of those."
    end

    # Descends into `ArrayFilter` wrappers built by `cover(["a", "b"])`.
    def collect_cover_globs(filter_list)
      filter_list.flat_map do |filter|
        case filter
        when GlobFilter then filter.filter_argument
        when ArrayFilter then collect_cover_globs(filter.filter_argument)
        else []
        end
      end
    end
  end
end
# frozen_string_literal: true

require_relative "../formatter/multi_formatter"

module SimpleCov
  module Configuration
    attr_writer :formatter, :print_error_status

    BUILT_IN_FORMATS = {
      html: :HTMLFormatter, json: :JSONFormatter, simple: :SimpleFormatter, baseline: :BaselineFormatter
    }.freeze
    private_constant :BUILT_IN_FORMATS

    LAZY_FORMAT_REQUIRES = {html: "../../covtool-html"}.freeze
    private_constant :LAZY_FORMAT_REQUIRES

    def formats(*names)
      return formatters if names.empty?

      self.formatters = names.map { |name| resolve_format(name) }
      formatters
    end

    def formatter(formatter = :__no_arg__)
      case formatter
      when :__no_arg__
        @formatter
      else
        @formatter = formatter || nil
      end
    end

    def formatters(formatters = :__no_arg__)
      case formatters
      when :__no_arg__
        configured = formatter
        configured ? [configured] : []
      else
        self.formatters = formatters
      end
    end

    # `nil`, `false`, and `[]` all opt out of formatting entirely. `false` is
    # normalized first, since `Array(false)` would otherwise smuggle it in as a
    # "formatter" that can only fail.
    def formatters=(formatters)
      @formatter = combined_formatter(Array(formatters || nil))
    end

    def color(value = :__no_arg__)
      return instance_variable_defined?(:@color) ? @color : :auto if value.eql?(:__no_arg__)

      self.color = _ = value
    end

    def color=(value)
      @color = value
    end

    def print_errors(value = :__no_arg__)
      return instance_variable_defined?(:@print_error_status) ? @print_error_status : true if value.eql?(:__no_arg__)

      self.print_errors = _ = value
    end

    def print_errors=(value)
      @print_error_status = value
    end

    def source_in_json(value = :__no_arg__)
      return instance_variable_defined?(:@source_in_json) ? @source_in_json : true if value.eql?(:__no_arg__)

      self.source_in_json = _ = value
    end

    def source_in_json=(value)
      @source_in_json = value
    end

    def print_error_status
      Deprecation.warn("`SimpleCov.print_error_status` is deprecated. " \
                       "Replace with `SimpleCov.print_errors` (same value).")
      instance_variable_defined?(:@print_error_status) ? @print_error_status : true
    end

    def nocov_token(nocov_token = nil)
      Deprecation.warn("`SimpleCov.nocov_token` and `SimpleCov.skip_token` are deprecated. " \
                       "Replace with `# covtool:disable` / `# covtool:enable` block comments.")
      current_nocov_token(nocov_token)
    end
    alias_method :skip_token, :nocov_token

    def current_nocov_token(value = nil)
      return @nocov_token if instance_variable_defined?(:@nocov_token) && value.nil?

      @nocov_token = value || "nocov"
    end

    private

    # An empty list is how a project opts out of formatting.
    def combined_formatter(formatters)
      return if formatters.empty?

      Formatter::MultiFormatter.new(formatters)
    end

    def resolve_format(name)
      return name unless name.instance_of?(Symbol)

      constant = BUILT_IN_FORMATS[name]
      unless constant
        raise ConfigurationError,
          "Unknown format #{name.inspect}. Built-in formats are :html, :json, :simple, and :baseline; " \
          "pass a formatter class or instance for anything else."
      end

      require_html_formatter(name)
      Formatter.const_get(constant)
    end

    # `formats :html` has to work in a process that never required the HTML
    # formatter, which under SIMPLECOV_NO_DEFAULTS nothing else has.
    def require_html_formatter(name)
      path = LAZY_FORMAT_REQUIRES[name]
      require_relative(path) if path
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    def groups
      @groups ||= {}
    end

    # The group set `SimpleCov.grouped` bins against when its caller names none.
    # It reads through a method of its own because the keyword it defaults
    # shadows `groups`, so the default has to name a receiver, and every
    # spelling of that receiver is the same call.
    #
    # mutant:disable — for that reason: `SimpleCov.groups`, `self.groups` and
    # `groups()` cannot be told apart.
    def default_groups
      groups
    end

    def groups=(new_groups)
      new_groups = new_groups.to_h { |name, filter| [GroupNames.normalize(name), filter] }
      GroupNames.validate!(new_groups.keys)
      @groups = new_groups
    end

    # Same matcher grammar as `skip`, but instead of dropping the matching files
    # it bins them under `group_name` for the formatter. Files matched by no
    # group fall into the implicit "Ungrouped" bucket.
    def group(group_name, filter_argument = nil, &)
      group_name = GroupNames.normalize(group_name)
      GroupNames.validate!([group_name])
      groups[group_name] = parse_filter(filter_argument, &)
    end

    def add_group(group_name, filter_argument = nil, &block)
      example = if block
        "`SimpleCov.group #{group_name.inspect} { ... }`"
      else
        "`SimpleCov.group #{group_name.inspect}, #{filter_argument.inspect}`"
      end
      Deprecation.warn(
        "`SimpleCov.add_group` is deprecated. " \
        "Replace with `SimpleCov.group` (same arguments, same behavior). Example: #{example}."
      )
      group(group_name, filter_argument, &block)
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    DROP_BASELINES = %i[last_run median branch].freeze

    # How many runs coverage/.history.json keeps, newest kept. 0 disables
    # recording entirely, and anything but a count of runs is refused.
    def history_limit(limit = nil)
      return @history_limit ||= 100 if limit.nil?

      self.history_limit = limit
      _ = @history_limit
    end

    def history_limit=(limit)
      unless limit.instance_of?(Integer) && limit >= 0
        raise ConfigurationError, "history_limit takes a non-negative integer, got #{limit.inspect}"
      end

      @history_limit = limit
    end

    # What `maximum_coverage_drop` measures the drop against: `:last_run` (the
    # default) the previous run whatever it was, `:median` the median of the
    # recorded history so one run that dipped for an unrelated reason cannot
    # quietly become the baseline, and `:branch` the newest recorded run on the
    # current git branch so a feature branch is compared with itself.
    #
    # The latter two read coverage/.history.json and find nothing to compare
    # against while it is empty, which counts as "no previous run" the way a
    # missing .last_run.json does.
    def drop_baseline(mode = nil)
      return @drop_baseline ||= :last_run if mode.nil?

      unless DROP_BASELINES.include?(mode)
        raise ConfigurationError,
          "drop_baseline takes one of #{DROP_BASELINES}, got #{mode.inspect}"
      end

      @drop_baseline = mode
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    IGNORABLE_BRANCH_TYPES = %i[implicit_else eval_generated].freeze
    IGNORABLE_METHOD_TYPES = %i[eval_generated].freeze

    # Deprecated in favour of `coverage(:branch) { ignore :implicit_else }`,
    # which fixes the criterion by context the way the threshold verbs do. One
    # difference rides out the deprecation period: the coverage block enables the
    # criterion it names, while this legacy setter records without enabling.
    def ignore_branches(*types)
      Deprecation.warn("`SimpleCov.ignore_branches` is deprecated. " \
                       "Replace with `coverage(:branch) { ignore #{types.map(&:inspect).join(", ")} }`.")
      store_ignored_branches(types)
    end

    def ignored_branches
      @ignored_branches ||= []
    end

    def ignored_branch?(type)
      ignored_branches.include?(type)
    end

    def ignore_methods(*types)
      Deprecation.warn("`SimpleCov.ignore_methods` is deprecated. " \
                       "Replace with `coverage(:method) { ignore #{types.map(&:inspect).join(", ")} }`.")
      store_ignored_methods(types)
    end

    def ignored_methods
      @ignored_methods ||= []
    end

    def ignored_method?(type)
      ignored_methods.include?(type)
    end

    private

    # Variadic semantics: multiple calls union, duplicates are no-ops, unknown
    # tokens raise.
    def store_ignored_branches(types)
      types.each { |type| raise_if_branch_type_unsupported(type) }
      ignored_branches.concat(types).uniq!
      ignored_branches
    end

    def store_ignored_methods(types)
      types.each { |type| raise_if_method_type_unsupported(type) }
      ignored_methods.concat(types).uniq!
      ignored_methods
    end

    def raise_if_branch_type_unsupported(type)
      return if IGNORABLE_BRANCH_TYPES.member?(type)

      raise ConfigurationError,
        "Unsupported branch type #{type.inspect} for `ignore_branches`. " \
        "Supported values are #{IGNORABLE_BRANCH_TYPES.inspect}"
    end

    def raise_if_method_type_unsupported(type)
      return if IGNORABLE_METHOD_TYPES.member?(type)

      raise ConfigurationError,
        "Unsupported method type #{type.inspect} for `ignore_methods`. " \
        "Supported values are #{IGNORABLE_METHOD_TYPES.inspect}"
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    #
    # Whether SimpleCov should hook `Process._fork` to attach itself to
    # subprocesses. Required when the suite uses parallel test workers (Rails'
    # `parallelize(workers:)`). Defaults to false.
    #
    def merge_subprocesses(value = nil)
      return @enable_for_subprocesses if instance_variable_defined?(:@enable_for_subprocesses) && value.nil?

      self.merge_subprocesses = value
      @enable_for_subprocesses
    end

    # false stands in for nothing, so the answer is always a real opt-in or
    # opt-out.
    def merge_subprocesses=(value)
      @enable_for_subprocesses = value || false
    end

    # @api private
    def enabled_for_subprocesses?
      !!@enable_for_subprocesses
    end

    #
    # Whether SimpleCov should auto-require the `parallel_tests` gem when it
    # sees `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` in the environment.
    # Defaults to auto-detect (nil). See #1018.
    #
    def parallel_tests(value = :__no_arg__)
      return @parallel_tests if value.eql?(:__no_arg__)

      self.parallel_tests = _ = value
    end

    def parallel_tests=(value)
      @parallel_tests = value
    end

    def enable_for_subprocesses(value = nil)
      Deprecation.warn("`SimpleCov.enable_for_subprocesses` is deprecated. " \
                       "Replace with `SimpleCov.merge_subprocesses` (same value, same behavior).")
      merge_subprocesses(value)
    end

    def merging(use = nil)
      self.merging = use unless use.nil?
      # Unset reads as nil, and only an explicit `merging false` turns it off.
      @use_merging = true if @use_merging.nil?
      @use_merging
    end

    def merging=(use)
      @use_merging = use
    end

    #
    # Whether SimpleCov's selected final process owns merge processing: waiting
    # for sibling workers, building the merged result, formatting, enforcing
    # thresholds, and writing `.last_run.json`.
    #
    # Defaults to true, except for recognized multi-worker parallel runs that
    # explicitly write to a custom coverage destination while merging is
    # enabled. Those runs are likely using an external `SimpleCov.collate` step
    # to finalize the merge.
    #
    # Splatted rather than defaulted: false is a value someone sets on purpose,
    # so "given nothing" cannot be told from it by looking at the argument.
    def finalize_merge(*value)
      unless value.empty?
        explicit, = value
        self.finalize_merge = _ = explicit
      end

      return @finalize_merge if @finalize_merge_explicit

      inferred = inferred_finalize_merge?
      warn_about_inferred_finalize_merge unless inferred
      inferred
    end

    # Writing is what makes the answer explicit rather than inferred.
    def finalize_merge=(value)
      @finalize_merge = value
      @finalize_merge_explicit = true
    end

    def finalize_merge?
      finalize_merge
    end

    # @api private
    def merge_finalization_owner?
      collating_result? || (finalize_merge? && final_result_process?)
    end

    def use_merging(use = nil)
      Deprecation.warn("`SimpleCov.use_merging` is deprecated. " \
                       "Replace with `SimpleCov.merging` (same value, same behavior).")
      merging(use)
    end

    #
    # The maximum age (in seconds) of a resultset to still be included in
    # merged results. Default is 600 seconds.
    #
    # A numeric SIMPLECOV_MERGE_TIMEOUT in the environment takes precedence
    # over the configured value: `covtool watch` re-runs test subsets across
    # a long session and extends its child runs' merge window this way, where
    # editing every watched project's configuration is not an option.
    #
    def merge_timeout(seconds = nil)
      self.merge_timeout = seconds
      # Memoized through a local rather than `|| (@merge_timeout ||= 600)`:
      # steep 2.0's logic-type interpreter crashes on an or-assignment nested in
      # a logical operand, and ivar narrowing doesn't carry across statements
      # the way a local's does.
      configured = @merge_timeout || 600
      @merge_timeout = configured
      env_merge_timeout || configured
    end

    # Anything but an Integer is ignored, the way the dual method always did.
    def merge_timeout=(seconds)
      @merge_timeout = seconds if seconds.instance_of?(Integer)
    end

    def env_merge_timeout
      value = ENV.fetch("SIMPLECOV_MERGE_TIMEOUT", nil)
      Integer(value, 10) if value&.match?(/\A\d+\z/)
    end

    #
    # How long (in seconds) the reporting process waits for the remaining
    # parallel-test workers to write their resultsets before it proceeds with a
    # partial merge. Default is 60 seconds. Raise it when a slow worker
    # routinely finishes well after the others, so its coverage is still
    # included and the threshold checks aren't skipped against a partial total.
    #
    def parallel_wait_timeout(seconds = nil)
      self.parallel_wait_timeout = seconds
      @parallel_wait_timeout ||= 60
    end

    # Anything but an Integer is ignored, the way the dual method always did.
    def parallel_wait_timeout=(seconds)
      @parallel_wait_timeout = seconds if seconds.instance_of?(Integer)
    end

    private

    def inferred_finalize_merge?
      return true unless merging

      adapter = ParallelAdapters.current
      return true unless adapter
      return true unless adapter.expected_worker_count > 1
      return true unless parallel_worker_environment?
      return true unless explicit_custom_coverage_destination?

      false
    end

    def parallel_worker_environment?
      ENV.key?("TEST_ENV_NUMBER") || ENV.key?("PARALLEL_TEST_GROUPS")
    end

    def explicit_custom_coverage_destination?
      return false unless explicit_coverage_destination?

      !coverage_path.eql?(File.expand_path("coverage", root))
    end

    def explicit_coverage_destination?
      @coverage_path_explicit || @coverage_dir_explicit
    end

    def warn_about_inferred_finalize_merge
      return if @finalize_merge_inference_warned
      return unless print_errors

      @finalize_merge_inference_warned = true
      warn Color.colorize(inferred_finalize_merge_warning, :yellow)
    end

    def inferred_finalize_merge_warning
      "SimpleCov inferred `finalize_merge false` because this parallel worker is merging " \
        "into a custom coverage destination. Set `SimpleCov.finalize_merge false` to keep " \
        "external collation ownership, or `SimpleCov.finalize_merge true` if this worker " \
        "should wait, merge, format, enforce thresholds, and write `.last_run.json`. " \
        "See https://github.com/covtool-ruby/covtool#merge-finalization-ownership."
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    # Caps the total number of misses per criterion. Where a percent minimum
    # asks for a ratio, this asks for an absolute burn-down number, which stays
    # meaningful as the codebase grows and shrinks.
    def maximum_missed(counts = nil)
      return @maximum_missed ||= {} unless counts

      @maximum_missed = normalized_missed_caps(counts, "maximum_missed")
    end

    # Unlike a percent minimum, which systematically flatters big files, this
    # holds every file to the same absolute budget. Files with a baseline entry
    # are exempt per covered criterion, as they are from the per-file minimum.
    def maximum_missed_per_file(counts = nil)
      return @maximum_missed_per_file ||= {} unless counts

      Deprecation.warn("`SimpleCov.maximum_missed_per_file` is deprecated. " \
                       "Replace it with:\n#{missed_per_file_replacement(counts)}")
      @maximum_missed_per_file = normalized_missed_caps(counts, "maximum_missed_per_file")
    end

    def maximum_missed_per_file_overrides
      @maximum_missed_per_file_overrides ||= {}
    end

    private

    def normalized_missed_caps(counts, setting)
      counts = {primary_coverage => counts} if counts.is_a?(Numeric)
      counts.each_key { |criterion| raise_if_criterion_disabled(criterion) }
      counts.each_value { |cap| raise_on_invalid_missed_cap(cap, setting) }
      _ = counts
    end

    def raise_on_invalid_missed_cap(cap, setting)
      return if cap.instance_of?(Integer) && cap >= 0

      raise ConfigurationError,
        "#{setting} takes a non-negative integer count of misses, got #{cap.inspect}"
    end

    def missed_per_file_replacement(counts)
      counts = {primary_coverage => counts} if counts.is_a?(Numeric)
      counts.map { |criterion, cap| "  coverage(#{criterion.inspect}) { maximum_missed #{cap}, per: :file }" }
        .join("\n")
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    # The path to a production coverage store, the file a `SimpleCov::Production`
    # sink wrote. Relative paths resolve against `SimpleCov.root`. The store is
    # read at report time, and an unreadable or invalid file warns and leaves the
    # section out, because a missing night's data should not fail the suite that
    # measured the tests.
    def production_coverage(path = nil)
      return @production_coverage if path.nil?

      self.production_coverage = path
      @production_coverage
    end

    def production_coverage=(path)
      raise ConfigurationError, "production_coverage takes a path, got #{path.inspect}" unless path.is_a?(String)

      @production_coverage = File.expand_path(path, root)
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    TRACK_TESTS_GRANULARITIES = %i[test file].freeze

    # Enables recording of which test covered which line. Off by default:
    # sampling coverage around every test costs run time, and the recorded map
    # costs space in `.resultset.json`. RSpec examples and Minitest tests are
    # wrapped automatically; other runners wrap their own units of work with
    # `SimpleCov.track_test`. A bare `track_tests` enables, and only an explicit
    # `track_tests false` turns it back off.
    #
    # `granularity` decides what one recorded context stands for: a test
    # (`:test`, the default) or a whole test file (`:file`). File granularity is
    # the batching lever for suites where per-test sampling costs too much.
    def track_tests(enabled = nil, granularity: nil)
      if granularity && !TRACK_TESTS_GRANULARITIES.include?(granularity)
        raise ConfigurationError,
          "Unsupported track_tests granularity #{granularity.inspect}, " \
          "supported values are #{TRACK_TESTS_GRANULARITIES.inspect}"
      end

      @track_tests_granularity = granularity if granularity
      @track_tests = enabled.nil? || enabled
    end

    def track_tests?
      !!@track_tests
    end

    def track_tests_granularity
      @track_tests_granularity || :test
    end

    # @api private. The map is built from per-line execution count deltas, which
    # `:oneshot_line` does not produce: a line reports only its first hit ever,
    # so every test after the first would show no delta.
    def validate_test_tracking!
      return unless track_tests?
      return if coverage_criterion_enabled?(DEFAULT_COVERAGE_CRITERION)

      raise ConfigurationError,
        "`track_tests` needs line coverage with execution counts. " \
        "Enable it with `enable_coverage :line` (`:oneshot_line` cannot record per-test data)."
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    def minimum_coverage(coverage = nil)
      return @minimum_coverage ||= {} unless coverage

      @minimum_coverage = normalized_threshold(coverage, "minimum_coverage")
    end

    def raise_on_invalid_coverage(coverage, coverage_setting)
      coverage.each_key { |criterion| raise_if_criterion_disabled(criterion) }
      coverage.each_value do |percent|
        minimum_possible_coverage_exceeded(coverage_setting) if percent && percent > 100
      end
    end

    #
    # The maximum overall coverage allowed for the testsuite to pass. Useful
    # paired with `minimum_coverage` (or via `expected_coverage`) to pin
    # coverage to an exact value, so an unexpected jump up fails the build
    # (#187).
    #
    def maximum_coverage(coverage = nil)
      return @maximum_coverage ||= {} unless coverage

      @maximum_coverage = normalized_threshold(coverage, "maximum_coverage")
    end

    def expected_coverage(coverage = nil)
      return minimum_coverage if coverage.nil?

      minimum_coverage(coverage)
      maximum_coverage(coverage)
    end

    def maximum_coverage_drop(coverage_drop = nil)
      return @maximum_coverage_drop ||= {} unless coverage_drop

      @maximum_coverage_drop = normalized_threshold(coverage_drop, "maximum_coverage_drop")
    end

    #
    # The minimum coverage per file required for the testsuite to pass.
    # Accepts a Numeric (global threshold on the primary criterion), a
    # Symbol-keyed Hash (per-criterion globals), or a Hash mixing Symbol keys
    # with String / Regexp keys to declare per-path overrides (#575).
    #
    def minimum_coverage_by_file(coverage = nil)
      return @minimum_coverage_by_file ||= {} unless coverage

      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)
      defaults, overrides = partition_per_file_thresholds(coverage)

      Deprecation.warn("`SimpleCov.minimum_coverage_by_file` is deprecated. " \
                       "Replace it with:\n#{per_file_coverage_replacement(defaults, overrides)}")

      raise_on_invalid_coverage(defaults, "minimum_coverage_by_file")
      overrides.each_value { |criteria| raise_on_invalid_coverage(criteria, "minimum_coverage_by_file") }

      @minimum_coverage_by_file = defaults
      @minimum_coverage_by_file_overrides = overrides
    end

    def minimum_coverage_by_file_overrides
      @minimum_coverage_by_file_overrides ||= {}
    end

    def minimum_coverage_by_group(coverage = nil)
      return @minimum_coverage_by_group ||= {} unless coverage

      Deprecation.warn("`SimpleCov.minimum_coverage_by_group` is deprecated. " \
                       "Replace it with:\n#{per_group_coverage_replacement(coverage)}")
      @minimum_coverage_by_group = coverage.to_h do |group_name, group_coverage|
        [GroupNames.normalize(group_name), normalized_threshold(group_coverage, "minimum_coverage_by_group")]
      end
    end

    def refuse_coverage_drop(*criteria)
      criteria = coverage_criteria if criteria.empty?
      maximum_coverage_drop(criteria.to_h { |c| [c, 0] })
    end

    private

    # A bare Numeric targets the primary criterion, and the resulting
    # per-criterion hash is validated before it is stored.
    def normalized_threshold(coverage, setting)
      coverage = {primary_coverage => coverage} if coverage.is_a?(Numeric)
      coverage.tap { |thresholds| raise_on_invalid_coverage(thresholds, setting) }
    end

    # Splits into Symbol-keyed criterion defaults and String/Regexp-keyed
    # per-path overrides, normalizing Numeric override values to
    # `{primary_coverage => N}` so downstream code has one shape to handle.
    def partition_per_file_thresholds(coverage)
      coverage.each_key { |key| validate_per_file_key(key) }
      # The assertions restate what the partition predicate guarantees: Symbol
      # keys carry per-criterion Numeric defaults, the rest are paths.
      symbol_pairs, path_pairs = coverage.partition { |key, _| key.instance_of?(Symbol) }
      defaults = symbol_pairs.to_h #: coverage_thresholds
      raw = path_pairs.to_h #: Hash[String | Regexp, Numeric | coverage_thresholds]
      overrides = raw.transform_values { |value| value.is_a?(Numeric) ? {primary_coverage => value} : value }
      [defaults, overrides]
    end

    def validate_per_file_key(key)
      # Symbols have no subclasses; paths and patterns may.
      return if key.instance_of?(Symbol) || key.is_a?(String) || key.is_a?(Regexp)

      raise ConfigurationError,
        "minimum_coverage_by_file keys must be Symbol (criterion), String, or Regexp; got #{key.inspect}"
    end

    def minimum_possible_coverage_exceeded(coverage_option)
      warn "The coverage you set for #{coverage_option} is greater than 100%"
    end

    # Renders the `coverage` configuration equivalent to a deprecated
    # `minimum_coverage_by_file` argument, so the deprecation warning can be
    # copy-pasted verbatim into the user's config.
    def per_file_coverage_replacement(defaults, overrides)
      by_criterion = {} #: Hash[Symbol, Array[String]]
      defaults.each { |criterion, percent| (by_criterion[criterion] ||= []) << "minimum #{percent}, per: :file" }
      overrides.each do |target, criteria|
        criteria.each do |criterion, percent|
          (by_criterion[criterion] ||= []) << "minimum #{percent}, per: #{target.inspect}"
        end
      end
      render_coverage_blocks(by_criterion)
    end

    def per_group_coverage_replacement(coverage)
      by_criterion = {} #: Hash[Symbol, Array[String]]
      coverage.each do |group_name, thresholds|
        normalized = (thresholds.is_a?(Numeric) ? {primary_coverage => thresholds} : thresholds) #: coverage_thresholds
        normalized.each do |criterion, percent|
          (by_criterion[criterion] ||= []) << "minimum #{percent}, per: group(#{group_name.inspect})"
        end
      end
      render_coverage_blocks(by_criterion)
    end

    def render_coverage_blocks(by_criterion)
      by_criterion.map do |criterion, statements|
        "  coverage(#{criterion.inspect}) { #{statements.join("; ")} }"
      end.join("\n")
    end
  end
end
# frozen_string_literal: true

module SimpleCov
  module Configuration
    DEFAULT_VIEW_GLOBS = %w[app/views/**/*.{erb,haml,slim}].freeze

    # Reports coverage for ActionView templates, defaulting to a Rails app's
    # views. Globs are expanded against `SimpleCov.root`, and one naming an
    # extension no handler is registered for (as the default does whenever a
    # project has no Haml or Slim) leaves those files out rather than reporting
    # them as empty.
    #
    # Templates the suite renders are measured through eval coverage, which this
    # enables. Templates it never renders are compiled at the end of the run so
    # they appear at 0% instead of going missing.
    def cover_views(*globs)
      globs = globs.flatten.compact
      globs = DEFAULT_VIEW_GLOBS.dup if globs.empty?
      @view_globs = globs
      enable_eval_coverage
      globs
    end

    # Nil rather than an empty Array when `cover_views` was never called, so
    # "not asked for" stays distinguishable from "asked for, with nothing to
    # match".
    def view_globs
      @view_globs
    end

    # False when eval coverage couldn't be enabled, where `cover_views` has
    # already warned and the templates would come back empty rather than at 0%.
    def view_coverage?
      !view_globs.nil? && coverage_for_eval_enabled?
    end
  end
end
# frozen_string_literal: true

require_relative "result_merger/legacy_format_adapter"
require_relative "result_merger/resultset_file"
require_relative "result_merger/resultset_run_identity"
require_relative "result_merger/resultset_store"
require_relative "result_merger/contexts"
require_relative "result_merger/unloaded_files"

module SimpleCov
  #
  # Caching, loading and merging `SimpleCov::Result`s into a single result for
  # coverage analysis based upon multiple test suites.
  #
  module ResultMerger
    extend ResultsetRunIdentity

    class << self
      def resultset_path
        ResultsetStore.resultset_path
      end

      def merge_and_store(*file_paths, ignore_timeout: false)
        result = merge_results(*file_paths, ignore_timeout: ignore_timeout)
        store_result(result) if result
        result
      end

      def merge_results(*file_paths, ignore_timeout: false)
        # Tracked paths and test maps are collected as each resultset is parsed,
        # so files are still read and discarded one at a time (#1250).
        tracked_files = Set.new
        context_maps = ContextMap::Union.new
        command_names, coverage = absorb_results(file_paths, ignore_timeout: ignore_timeout,
          &entry_collector(tracked_files, context_maps))
        create_result(command_names, coverage, tracked_files: tracked_files, contexts: context_maps.map,
          contexts_dropped: context_maps.dropped)
      end

      # One block over the entries each resultset contributes to the merge,
      # feeding every merge-side accumulator in a single pass: the tracked
      # paths and the per-test map union (#1250).
      def entry_collector(tracked_files, context_maps)
        collectors = [UnloadedFiles.collector(tracked_files), context_maps.collector]
        ->(surviving) { collectors.each { |collector| collector.call(surviving) } }
      end

      #
      # Reads every resultset and folds it into one merged coverage, stopping
      # short of building a `SimpleCov::Result`.
      #
      # Files are only read in and parsed one at a time on purpose. In big CI
      # setups you might deal with 100s of jobs each producing megabytes of
      # data, and reading them all in easily produces gigabytes of memory
      # consumption. For the same reason a `Result` is only created at the end.
      #
      # One accumulator absorbs the whole run, rather than folding each file
      # into the merged-so-far pairwise: the pairwise form rebuilt every file's
      # coverage once per resultset, which is what made merging a large
      # parallel run's results the dominant cost of `collate`.
      #
      # `file_paths` is only ever iterated, so a caller that wants to observe
      # the merge as it goes can hand in any Enumerable. `benchmarks/collate`
      # passes an Enumerator that reports progress.
      #
      def absorb_results(file_paths, ignore_timeout: false, &on_parse)
        Combine::CoverageAccumulator.fold(
          file_paths.lazy.map { |file_path| valid_results(file_path, ignore_timeout: ignore_timeout, &on_parse) }
        )
      end

      # Yields the surviving entries before they are reduced.
      def valid_results(file_path, ignore_timeout: false, &on_parse)
        merge_valid_results(ResultsetFile.parse(file_path), ignore_timeout: ignore_timeout, &on_parse)
      end

      # Yields the entries that survived the merge timeout, so a caller that
      # wants to observe what a resultset carried sees only what is being
      # merged. An expired entry contributes nothing, tracked paths included.
      def merge_valid_results(results, ignore_timeout: false)
        results = drop_expired_results(results) unless ignore_timeout
        yield results if block_given?

        command_plus_coverage = results.map do |command_name, data|
          [[command_name], LegacyFormatAdapter.call(data.fetch("coverage"))]
        end

        merge_coverage(*command_plus_coverage)
      end

      def drop_expired_results(results)
        fresh, expired = results.partition { |_command_name, data| within_merge_timeout?(data) }
        return results if expired.empty?

        warn_about_expired_results(expired.map(&:first))
        fresh.to_h
      end

      def within_merge_timeout?(data)
        (Time.now - Time.at(data.fetch("timestamp"))) < SimpleCov.merge_timeout
      end

      def warn_about_expired_results(expired_command_names)
        # Ordinary parallel workers only store their own slice; the selected
        # final process performs this merge.
        return unless SimpleCov.print_errors

        warn "[SimpleCov]: Excluded #{expired_command_names.size} result(s) older than " \
             "merge_timeout (#{SimpleCov.merge_timeout}s) from the merged report: " \
             "#{expired_command_names.sort.join(", ")}. " \
             "Increase SimpleCov.merge_timeout to include them."
      end

      # `tracked_files:` has no default: only the caller knows what the
      # contributing processes were told to track, and quietly reading an
      # omission as "nothing was tracked" would drop every never-loaded
      # file from the merged report.
      def create_result(command_names, coverage, tracked_files:, contexts: nil, contexts_dropped: nil)
        return nil unless coverage

        # Deduped: a CI matrix collates one resultset per worker, and joining
        # every run's name verbatim rendered "RSpec" a hundred times over in the
        # report footer (#1284).
        distinct_names = command_names.reject(&:empty?).uniq.sort
        coverage, injected = UnloadedFiles.inject(coverage, tracked_files)
        # The merged result is the authoritative one users actually see, so it's
        # the one that warns about source files dropped because they no longer
        # exist on disk (#980). The per-process slices stay quiet to avoid one
        # warning per worker.
        Result.new(
          coverage,
          command_name: distinct_names.join(", "), contexts: contexts, contexts_dropped: contexts_dropped, report: true,
          not_loaded_files: UnloadedFiles.never_executed(coverage) | injected,
          tracked_files: tracked_files
        ).tap { |result| result.command_names = distinct_names }
      end

      def merge_coverage(*results)
        return [[""], nil] if results.empty?

        # Destructured rather than counted: the single-result fast path then
        # hands back the very result it checked for, not a second lookup.
        only, *rest = results
        rest.empty? ? only : Combine::CoverageAccumulator.fold(results)
      end

      def merged_result
        tracked_files = Set.new
        context_maps = ContextMap::Union.new
        command_names, coverage = merge_valid_results(read_resultset, &entry_collector(tracked_files, context_maps))
        create_result(command_names, coverage, tracked_files: tracked_files, contexts: context_maps.map,
          contexts_dropped: context_maps.dropped)
      end

      def read_resultset
        content = synchronize_resultset { ResultsetFile.read(resultset_path) }
        ResultsetFile.decode(content)
      end

      def store_result(result)
        synchronize_resultset do
          new_resultset = read_resultset

          # A single result only ever has one command_name, see `Result#to_hash`.
          command_name, data = result.to_hash.first
          new_resultset[command_name] = merged_entry(new_resultset[command_name], data)

          ResultsetStore.write(new_resultset)
        end
        true
      end

      # If an entry with the same command_name was written AFTER our process
      # started, a sibling test runner wrote it. Combine coverage data rather
      # than overwriting, so an empty parent-process result doesn't clobber the
      # subprocess's real data (#581). An earlier run's entry is replaced, all
      # but its test map.
      def merged_entry(existing, incoming)
        return Contexts.carry_forward(incoming, existing) unless concurrent_runner_entry?(existing, incoming)

        merged = incoming.merge(
          "coverage" => Combine::ResultsCombiner.combine(existing.fetch("coverage"), incoming.fetch("coverage"))
        )
        merged = Contexts.carry(merged, existing, incoming)
        UnloadedFiles.carry_tracked(merged, existing, incoming)
      end

      def synchronize_resultset(&)
        ResultsetStore.synchronize(&)
      end
    end
  end
end
