# frozen_string_literal: true

module SimpleCov
  class Result
    # When a resultset references source files that don't exist on the local
    # filesystem they're silently dropped — which produces an empty `0 / 0
    # (100.00%)` report that looks like success but isn't. Emit a single
    # warning summarizing the drop and, when every entry was lost, point at
    # the typical cause (`SimpleCov.collate` invoked from a machine or path
    # different from where the resultsets were generated). See #980.
    class MissingSourceFilesReporter
      def initialize(missing_paths, input_size:, every_entry_dropped:)
        @missing_paths = missing_paths
        @input_size = input_size
        @every_entry_dropped = every_entry_dropped
      end

      def warn!
        warn SimpleCov::Color.colorize(message, :yellow)
      end

      def message
        @every_entry_dropped ? all_missing_warning : partial_missing_warning
      end

    private

      def all_missing_warning
        "SimpleCov dropped all #{@missing_paths.size} source file(s) from the result — " \
          "none of the paths in the resultset exist on this filesystem: " \
          "#{summary}. If you're running `SimpleCov.collate`, the source " \
          "files must be available at the same absolute paths as when the individual resultsets " \
          "were generated."
      end

      def partial_missing_warning
        "SimpleCov dropped #{@missing_paths.size} source file(s) from the result because " \
          "they don't exist on this filesystem: #{summary}. They were " \
          "tracked in the resultset but have since moved or been removed."
      end

      def summary
        sample = @missing_paths.first(5).join(", ")
        remaining = @missing_paths.size - 5
        remaining.positive? ? "#{sample} (+#{remaining} more)" : sample
      end
    end
  end
end
