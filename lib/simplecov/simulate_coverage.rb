# frozen_string_literal: true

module SimpleCov
  #
  # Responsible for producing file coverage metrics.
  #
  module SimulateCoverage
  module_function

    #
    # Simulate a file coverage report for a file that was tracked but never
    # required. Returns the same hash shape as `Coverage.result` (lines,
    # branches, methods).
    #
    # The line classification comes from `Coverage.line_stub` — the same
    # classification the runtime would have produced if the file had been
    # required — overlaid with SimpleCov's `# :nocov:` toggles and
    # `# simplecov:disable line` directive ranges, which `Coverage` doesn't
    # know about. This keeps "relevant lines" identical whether a file was
    # loaded or just tracked, fixing the multi-line statement discrepancy
    # in https://github.com/simplecov-ruby/simplecov/issues/654.
    #
    # @return [Hash]
    #
    def call(absolute_path)
      source_lines = read_lines(absolute_path)
      lines = coverage_stub(absolute_path, source_lines) ||
              LinesClassifier.new.classify(source_lines)

      {
        "lines" => lines,
        # we don't want to parse branches/methods ourselves...
        # requiring files can have side effects and we don't want to trigger that
        "branches" => {},
        "methods" => {}
      }
    end

    def read_lines(path)
      File.readlines(path)
    rescue Errno::ENOENT
      []
    end

    # Combine `Coverage.line_stub` (which gets multi-line statements right)
    # with `LinesClassifier` (which knows about `# :nocov:` toggles and
    # `# simplecov:disable line` ranges). Returns nil — and the caller
    # falls back to `LinesClassifier` alone — when `Coverage` can't read
    # or parse the file, or when the runtime doesn't expose `line_stub`
    # (JRuby and TruffleRuby).
    def coverage_stub(path, source_lines)
      return nil unless Coverage.respond_to?(:line_stub)

      stub = Coverage.line_stub(path)
      classifier_output = LinesClassifier.new.classify(source_lines)
      stub.each_index { |idx| stub[idx] = nil if classifier_output[idx].nil? }
      stub
    rescue Errno::ENOENT, SyntaxError
      nil
    end
  end
end
