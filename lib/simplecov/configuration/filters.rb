# frozen_string_literal: true

module SimpleCov
  # Inclusion / exclusion / grouping DSL: `cover`, `skip`, `group`,
  # plus the deprecated `track_files` / `add_filter` / `add_group`
  # aliases. Mutates the same `filters`, `groups`, and `cover_filters`
  # collections the main Configuration module exposes.
  module Configuration
    attr_writer :filters, :groups

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

    # Returns the list of configured inclusion filters added via `cover`.
    def cover_filters
      @cover_filters ||= []
    end

    # Returns the list of string globs passed to `cover` — used by the
    # disk-discovery pass in `SimpleCov.add_not_loaded_files` so files
    # matching a `cover` glob appear in the report even when they were
    # never required during the suite.
    #
    # Walks into `ArrayFilter` entries (built when a caller passes an
    # array to `cover`) so a glob nested inside `cover(["lib/**/*.rb",
    # /helper\.rb\z/])` still drives unloaded-file discovery.
    def cover_globs
      collect_cover_globs(cover_filters)
    end

    # DEPRECATED: prefer `cover`, which both includes unloaded files (the
    # historical `track_files` behavior) and restricts the report to the
    # matching set.
    def track_files(glob)
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.track_files` is deprecated. " \
           "#{track_files_replacement_hint(glob)}"
      @tracked_files = glob
    end

    # `track_files(nil)` is the documented way to clear a previously-set
    # glob, but `cover(nil)` raises `ConfigurationError`, so don't point
    # users at it. The `cover` API has no direct equivalent for "reset
    # the inclusion list" — point users at the `@cover_filters` reset.
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

    # Returns the glob used to include files that were not explicitly required.
    def tracked_files
      @tracked_files if defined?(@tracked_files)
    end

    # Returns the list of configured exclusion filters added via `skip`
    # (or the deprecated `add_filter`).
    def filters
      @filters ||= []
    end

    #
    # Drop matching files from the coverage report. The inverse of `cover`.
    #
    # See README for the full grammar; `skip` accepts a String (path-segment
    # substring), Regexp, block predicate, or Array of any of those.
    #
    def skip(filter_argument = nil, &)
      filters << parse_filter(filter_argument, &)
    end

    # DEPRECATED: alias for `skip`. Same matcher grammar, identical behavior.
    def add_filter(filter_argument = nil, &block)
      example = block ? "`SimpleCov.skip { ... }`" : "`SimpleCov.skip #{filter_argument.inspect}`"
      warn "#{Kernel.caller.first}: [DEPRECATION] `SimpleCov.add_filter` is deprecated. " \
           "Replace with `SimpleCov.skip` (same arguments, same behavior). Example: #{example}."
      skip(filter_argument, &block)
    end

    # Remove any filters whose `filter_argument` equals the given value.
    # Returns true when at least one filter was removed, false otherwise.
    def remove_filter(filter_argument) # rubocop:disable Naming/PredicateMethod
      before = filters.size
      filters.reject! { |filter| filter.respond_to?(:filter_argument) && filter.filter_argument == filter_argument }
      filters.size != before
    end

    # Remove every filter from the chain, including the defaults installed
    # by `SimpleCov.start`.
    def clear_filters
      @filters = []
    end

    # Returns the configured groups. Add groups using SimpleCov.group.
    def groups
      @groups ||= {}
    end

    # Define a display group for files. Same matcher grammar as `skip`,
    # but instead of dropping the matching files it bins them under
    # `group_name` for the formatter. Files matched by no group fall
    # into the implicit "Ungrouped" bucket.
    def group(group_name, filter_argument = nil, &)
      groups[group_name] = parse_filter(filter_argument, &)
    end

    # DEPRECATED: alias for `group`. Same arguments, same behavior.
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

    # Drop every filter previously installed (defaults plus anything
    # earlier in this block) so subsequent `skip` calls start from a
    # clean slate. Order matters — call this before your own `skip`
    # invocations.
    def no_default_skips
      clear_filters
    end

  private

    # The actual filter processor. Not meant for direct use.
    def parse_filter(filter_argument = nil, &filter_proc)
      filter = filter_argument || filter_proc

      raise ArgumentError, "Please specify either a filter or a block to filter with" unless filter

      SimpleCov::Filter.build_filter(filter)
    end

    # Build a filter for a `cover` argument. Strings are treated as
    # globs (not substrings — that's `skip`/`add_filter`'s semantics).
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
