# frozen_string_literal: true

module SimpleCov
  #
  # Base filter class. Inherit from this to create custom filters, and
  # override `matches?(source_file)`.
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
    # tracked files a process did not load. Defaults to false so a custom
    # filter is never guessed at (#1250).
    def path_only?
      false
    end

    # `string_filter` selects the semantics of bare String arguments:
    # StringFilter's segment-substring match for `skip`, GlobFilter for
    # `cover`. It threads through Array elements so a list gets the same
    # treatment as its members.
    def self.build_filter(filter_argument, string_filter: StringFilter)
      case filter_argument
      when Filter then filter_argument
      when String then string_filter.new(filter_argument)
      when Array
        ArrayFilter.new(filter_argument.map { |arg| build_filter(arg, string_filter: string_filter) })
      else class_for_argument(filter_argument).new(filter_argument)
      end
    end

    def self.class_for_argument(filter_argument)
      filter_classes_by_argument_type.find { |type, _| filter_argument.is_a?(type) }&.last ||
        raise(ConfigurationError, "You have provided an unrecognized filter type")
    end

    def self.filter_classes_by_argument_type
      @filter_classes_by_argument_type ||= {
        String => StringFilter,
        Regexp => RegexFilter,
        Array => ArrayFilter,
        Proc => BlockFilter
      }.freeze
    end
    private_class_method :filter_classes_by_argument_type
  end

  class StringFilter < Filter
    # Matching is path-segment-aware: the argument must appear immediately
    # after a "/" and be followed by "/" or end-of-string, so "lib" matches
    # "/lib/foo.rb" but not "/app/models/library.rb".
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
        # Bare filename pattern ("test.rb" matches "faked_test.rb"): allow a
        # substring match within a single path segment. Multi-segment arguments
        # must not get this relaxation, or "app/models/user.rb" would also
        # match "webapp/models/user.rb".
        %r{#{boundary}[^/]*#{escaped}(?=[/.]|\z)}
      else
        # Require a segment-boundary match so "lib" matches "lib/" but not
        # "library/".
        %r{#{boundary}#{escaped}(?=[/.]|\z)}
      end
    end
  end

  class RegexFilter < Filter
    # `Regexp#match?` rather than `=~` so the predicate returns a real boolean:
    # `=~` would return the match position, which trips rspec-mocks 4's
    # stricter predicate-matcher type check.
    def matches?(source_file)
      filter_argument.match?(source_file.project_filename)
    end

    def path_only?
      true
    end
  end

  class BlockFilter < Filter
    def matches?(source_file)
      filter_argument.call(source_file)
    end
  end

  # Matches when the source file's project path matches the configured shell
  # glob. Used by `cover`, and by `skip` when callers want glob semantics
  # instead of `StringFilter`'s substring match.
  class GlobFilter < Filter
    def matches?(source_file)
      File.fnmatch?(filter_argument, source_file.project_filename, File::FNM_PATHNAME | File::FNM_EXTGLOB)
    end

    def path_only?
      true
    end
  end

  class ArrayFilter < Filter
    def initialize(filter_argument)
      filter_objects = filter_argument.map do |arg|
        Filter.build_filter(arg)
      end

      super(filter_objects)
    end

    def path_only?
      filter_argument.all?(&:path_only?)
    end

    def matches?(source_files_list)
      filter_argument.any? do |arg|
        arg.matches?(source_files_list)
      end
    end
  end
end
