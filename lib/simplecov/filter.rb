# frozen_string_literal: true

module SimpleCov
  #
  # Base filter class. Inherit from this to create custom filters,
  # and overwrite the passes?(source_file) instance method
  #
  # # A sample class that rejects all source files.
  # class StupidFilter < SimpleCov::Filter
  #   def passes?(source_file)
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
      raise "The base filter class is not intended for direct use"
    end

    def passes?(source_file)
      warn "#{Kernel.caller.first}: [DEPRECATION] #passes? is deprecated. Use #matches? instead."
      matches?(source_file)
    end

    def self.build_filter(filter_argument)
      return filter_argument if filter_argument.is_a?(SimpleCov::Filter)

      class_for_argument(filter_argument).new(filter_argument)
    end

    def self.class_for_argument(filter_argument)
      filter_classes_by_argument_type.find { |type, _| filter_argument.is_a?(type) }&.last ||
        raise(ArgumentError, "You have provided an unrecognized filter type")
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

  private

    def segment_pattern
      @segment_pattern ||= compute_segment_pattern
    end

    def compute_segment_pattern
      normalized = filter_argument.delete_prefix("/")
      escaped    = Regexp.escape(normalized)
      boundary   = '(?:\A|/)'

      if normalized.include?(".")
        # Filename pattern (e.g. "test.rb" matches "faked_test.rb"): allow
        # substring match within the last path segment, anchored to a
        # segment boundary.
        %r{#{boundary}[^/]*#{escaped}}
      elsif normalized.end_with?("/")
        # Trailing slash signals directory-only matching.
        /#{boundary}#{escaped}/
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
    # regex configured when initializing this Filter with RegexFilter.new(/someregex/)
    def matches?(source_file)
      (source_file.project_filename =~ filter_argument)
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

  # Filter that matches when any of its component filters (built from the
  # array's elements) match the source file.
  class ArrayFilter < SimpleCov::Filter
    def initialize(filter_argument)
      filter_objects = filter_argument.map do |arg|
        Filter.build_filter(arg)
      end

      super(filter_objects)
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
