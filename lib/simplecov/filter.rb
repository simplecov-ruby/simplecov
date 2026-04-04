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
      case filter_argument
      when String
        SimpleCov::StringFilter
      when Regexp
        SimpleCov::RegexFilter
      when Array
        SimpleCov::ArrayFilter
      when Proc
        SimpleCov::BlockFilter
      else
        raise ArgumentError, "You have provided an unrecognized filter type"
      end
    end
  end

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
      @segment_pattern ||= begin
        normalized = filter_argument.delete_prefix("/")
        if normalized.include?(".")
          # Contains a dot — looks like a filename pattern. Allow substring
          # match within the last path segment (e.g. "test.rb" matches
          # "faked_test.rb") while still anchoring to a "/" boundary.
          %r{/[^/]*#{Regexp.escape(normalized)}}
        else
          # No dot — looks like a directory or path. Require segment-boundary
          # match so "lib" matches "/lib/" but not "/library/".
          if normalized.end_with?("/")
            # Trailing slash signals directory-only matching
            %r{/#{Regexp.escape(normalized)}}
          else
            %r{/#{Regexp.escape(normalized)}(?=[/.]|$)}
          end
        end
      end
    end
  end

  class RegexFilter < SimpleCov::Filter
    # Returns true when the given source file's filename matches the
    # regex configured when initializing this Filter with RegexFilter.new(/someregex/)
    def matches?(source_file)
      (source_file.project_filename =~ filter_argument)
    end
  end

  class BlockFilter < SimpleCov::Filter
    # Returns true if the block given when initializing this filter with BlockFilter.new {|src_file| ... }
    # returns true for the given source file.
    def matches?(source_file)
      filter_argument.call(source_file)
    end
  end

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
