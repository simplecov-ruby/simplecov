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
        when GlobFilter  then filter.filter_argument
        when ArrayFilter then collect_cover_globs(filter.filter_argument)
        else []
        end
      end
    end
  end
end
