# frozen_string_literal: true

module SimpleCov
  #
  # Base filter class. Inherit from this to create custom filters,
  # and overwrite the matches?(source_file) instance method
  #
  # # A sample class that rejects all source files.
  # class StupidFilter < SimpleCov::Filter
  #   def matches?(source_file)
  #     false
  #   end
  # end
  #
  class Filter
    attr_reader :filter_argument

    def initialize(filter_argument)
      @filter_argument = filter_argument
    end

    def matches?(_source_file)
      raise NotImplementedError, "The base filter class is not intended for direct use"
    end

    # Whether this filter's verdict depends only on the file's path, so it can
    # be decided before that file has any coverage. Used when recording which
    # tracked files a process did not load, where no coverage exists yet.
    # Defaults to false so a custom filter is never guessed at. See #1250.
    def path_only?
      false
    end

    # `string_filter` selects the semantics of bare String arguments —
    # StringFilter's segment-substring match for `skip`,
    # GlobFilter for `cover` — and threads through Array elements so a
    # list gets the same treatment as its members.
    def self.build_filter(filter_argument, string_filter: SimpleCov::StringFilter)
      case filter_argument
      when SimpleCov::Filter then filter_argument
      when String            then string_filter.new(filter_argument)
      when Array
        SimpleCov::ArrayFilter.new(filter_argument.map { |arg| build_filter(arg, string_filter: string_filter) })
      else class_for_argument(filter_argument).new(filter_argument)
      end
    end

    def self.class_for_argument(filter_argument)
      filter_classes_by_argument_type.find { |type, _| filter_argument.is_a?(type) }&.last ||
        raise(SimpleCov::ConfigurationError, "You have provided an unrecognized filter type")
    end

    def self.filter_classes_by_argument_type
      @filter_classes_by_argument_type ||= {
        String => SimpleCov::StringFilter,
        Regexp => SimpleCov::RegexFilter,
        Array => SimpleCov::ArrayFilter,
        Proc => SimpleCov::BlockFilter
      }.freeze
    end
    private_class_method :filter_classes_by_argument_type
  end

  # Filter that matches when the source file's project path contains the
  # configured string at a path-segment boundary.
  class StringFilter < SimpleCov::Filter
    # Returns true when the given source file's filename matches the
    # string configured when initializing this Filter with StringFilter.new('somestring').
    # Matching is path-segment-aware: the argument must appear immediately after a "/"
    # and be followed by "/" or end-of-string, so "lib" matches "/lib/foo.rb" but not
    # "/app/models/library.rb".
    def matches?(source_file)
      source_file.project_filename.match?(segment_pattern)
    end

    def path_only?
      true
    end

  private

    def segment_pattern
      @segment_pattern ||= compute_segment_pattern
    end

    def compute_segment_pattern
      normalized = filter_argument.delete_prefix("/")
      escaped    = Regexp.escape(normalized)
      boundary   = '(?:\A|/)'

      if normalized.end_with?("/")
        # Trailing slash signals directory-only matching.
        /#{boundary}#{escaped}/
      elsif normalized.include?(".") && !normalized.include?("/")
        # Bare filename pattern (e.g. "test.rb" matches "faked_test.rb"):
        # allow a substring match within a single path segment. Multi-segment
        # arguments must not get this relaxation, or "app/models/user.rb"
        # would also match "webapp/models/user.rb".
        %r{#{boundary}[^/]*#{escaped}(?=[/.]|\z)}
      else
        # Directory or path: require a segment-boundary match so "lib"
        # matches "lib/" but not "library/".
        %r{#{boundary}#{escaped}(?=[/.]|\z)}
      end
    end
  end

  # Filter that matches when the source file's project path matches the
  # configured Regexp.
  class RegexFilter < SimpleCov::Filter
    # Returns true when the given source file's filename matches the
    # regex configured when initializing this Filter with RegexFilter.new(/someregex/).
    # Uses `Regexp#match?` so the predicate returns a real boolean — `=~`
    # would return the match position (an Integer or nil), which trips
    # rspec-mocks 4's stricter predicate-matcher type check.
    def matches?(source_file)
      filter_argument.match?(source_file.project_filename)
    end

    def path_only?
      true
    end
  end

  # Filter that matches when the configured block returns truthy for the
  # source file.
  class BlockFilter < SimpleCov::Filter
    # Returns true if the block given when initializing this filter with BlockFilter.new {|src_file| ... }
    # returns true for the given source file.
    def matches?(source_file)
      filter_argument.call(source_file)
    end
  end

  # Filter that matches when the source file's project path matches the
  # configured shell glob (e.g. "lib/**/*.rb"). Used by `cover` and
  # `skip` when callers want glob semantics instead of the substring
  # match of `StringFilter`.
  class GlobFilter < SimpleCov::Filter
    def matches?(source_file)
      File.fnmatch?(filter_argument, source_file.project_filename, File::FNM_PATHNAME | File::FNM_EXTGLOB)
    end

    def path_only?
      true
    end
  end

  # Filter that matches when any of its component filters (built from the
  # array's elements) match the source file.
  class ArrayFilter < SimpleCov::Filter
    def initialize(filter_argument)
      filter_objects = filter_argument.map do |arg|
        Filter.build_filter(arg)
      end

      super(filter_objects)
    end

    # Path-decidable only when every component filter is.
    def path_only?
      filter_argument.all?(&:path_only?)
    end

    # Returns true if any of the filters in the array match the given source file.
    # Configure this Filter like StringFilter.new(['some/path', /^some_regex/, Proc.new {|src_file| ... }])
    def matches?(source_files_list)
      filter_argument.any? do |arg|
        arg.matches?(source_files_list)
      end
    end
  end
end
