# frozen_string_literal: true

module SimpleCov
  # Inclusion and exclusion methods: `cover` and `skip`.
  module Configuration
    attr_writer :filters

    #
    # Restrict the universe of files in the coverage report to those matching
    # one or more globs, regexps, or block predicates. Multiple calls union;
    # when any `cover` matcher is configured the report drops every file that
    # doesn't match at least one of them.
    #
    # Strings are interpreted as shell globs (e.g. "lib/**/*.rb"), not
    # substring matches — a deliberate departure from `skip`, which reads a
    # String as a path-segment substring.
    #
    # When the matcher is a string-glob, `cover` also expands the glob on
    # disk so files that exist but were never required during the run still
    # appear in the report (at 0% coverage).
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
    # disk-discovery pass in `SimpleCov.tracked_file_paths` so files
    # matching a `cover` glob appear in the report even when they were
    # never required during the suite.
    #
    # Walks into `ArrayFilter` entries (built when a caller passes an
    # array to `cover`) so a glob nested inside `cover(["lib/**/*.rb",
    # /helper\.rb\z/])` still drives unloaded-file discovery.
    def cover_globs
      collect_cover_globs(cover_filters)
    end

    # @api private — the additive disk-discovery glob. `cover` is the
    # public way to pull unloaded files into the report; this remains for
    # the bundled `rails` profile, which sets the ivar directly to keep
    # discovery additive without also restricting the report's universe.
    def tracked_files
      @tracked_files if defined?(@tracked_files)
    end

    # Returns the list of configured exclusion filters added via `skip`.
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
    # globs (not substrings — that's `skip`'s semantics); everything else
    # dispatches exactly like `skip`.
    def build_cover_filter(arg)
      SimpleCov::Filter.build_filter(arg, string_filter: SimpleCov::GlobFilter)
    rescue SimpleCov::ConfigurationError
      raise SimpleCov::ConfigurationError, "Unsupported `cover` argument #{arg.inspect}; " \
                                           "expected a String glob, Regexp, Proc, " \
                                           "SimpleCov::Filter, or Array of those."
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
