# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Builds the `SourceFile::Method` objects for a source file from
    # the raw method-coverage data. Applies the
    # `ignore_methods :eval_generated` filter and marks methods inside
    # `# simplecov:disable` / `# :nocov:` chunks as skipped.
    class MethodBuilder
      def initialize(source_file)
        @source_file = source_file
      end

      def call
        methods = @source_file.coverage_data.fetch("methods", {}).filter_map do |info, hit_count|
          info = RubyDataParser.call(info)
          next if eval_generated_to_ignore?(info)

          SourceFile::Method.new(@source_file, info, hit_count)
        end

        process_skipped(methods)
      end

    private

      # See `BranchBuilder#eval_generated_condition_to_ignore?` for the
      # rationale. Coverage reports an eval'd `def` at the eval caller's
      # line and name, so a method whose `(name, start_line)` is absent
      # from the real-source `def` set is eval-generated. Only consulted
      # when the user has opted in via
      # `SimpleCov.ignore_methods :eval_generated`. See #1046.
      def eval_generated_to_ignore?(info)
        return false unless SimpleCov.ignored_method?(:eval_generated)

        positions = @source_file.real_source_positions
        # simplecov:disable branch — nil branch fires only when Prism is unavailable
        return false unless positions

        # simplecov:enable branch

        _class_name, name, start_line, * = info
        !positions[:methods].include?([name, start_line])
      end

      def process_skipped(methods)
        chunks = @source_file.skip_chunks_for(:method)
        return methods if chunks.empty?

        methods.each do |method|
          method.skipped! if chunks.any? { |chunk| method.overlaps_with?(chunk) }
        end

        methods
      end
    end
  end
end
