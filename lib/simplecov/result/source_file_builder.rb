# frozen_string_literal: true

module SimpleCov
  class Result
    class SourceFileBuilder
      attr_reader :missing_source_files

      def initialize(original_result, not_loaded_files:)
        @original_result = original_result
        @not_loaded_files = not_loaded_files
        @missing_source_files = []
      end

      def call
        FileList.new(
          @original_result
            .filter_map { |filename, coverage| build_source_file(filename, coverage) }
            .sort_by(&:filename)
        )
      end

    private

      def build_source_file(filename, coverage)
        unless File.file?(filename)
          @missing_source_files << filename
          return
        end

        SourceFile.new(
          filename,
          stringify_outer_keys(coverage),
          loaded: !@not_loaded_files.include?(filename)
        )
      end

      # `Coverage.result` returns symbol keys; resultsets loaded from disk are
      # already string-keyed. SourceFile reads with strings and handles both Array
      # and stringified-Array branch/method keys itself, so only the outer hash
      # needs normalizing.
      def stringify_outer_keys(coverage)
        coverage.transform_keys(&:to_s)
      end
    end
  end
end
