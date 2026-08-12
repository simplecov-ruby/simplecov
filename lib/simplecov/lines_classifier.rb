# frozen_string_literal: true

require_relative "directive"

module SimpleCov
  # Classifies whether lines are relevant for code coverage analysis.
  # Comments and whitespace lines, and lines inside a `# simplecov:disable`
  # block, are considered not relevant.
  class LinesClassifier
    RELEVANT = 0
    NOT_RELEVANT = nil

    WHITESPACE_LINE = /^\s*$/
    COMMENT_LINE = /^\s*#/
    WHITESPACE_OR_COMMENT_LINE = Regexp.union(WHITESPACE_LINE, COMMENT_LINE)

    def self.whitespace_line?(line)
      WHITESPACE_OR_COMMENT_LINE.match?(line)
    rescue ArgumentError
      # E.g., line contains an invalid byte sequence in UTF-8
      false
    end

    def classify(lines)
      lines = lines.to_a
      directive_disabled = directive_disabled_line_set(lines)

      lines.map.with_index(1) do |line, line_number|
        classify_line(line, line_number, directive_disabled)
      end
    end

  private

    def classify_line(line, line_number, directive_disabled)
      if self.class.whitespace_line?(line) || directive_disabled.include?(line_number)
        NOT_RELEVANT
      else
        RELEVANT
      end
    end

    def directive_disabled_line_set(lines)
      Directive.disabled_ranges(lines).fetch(:line).each_with_object(Set.new) do |range, set|
        range.each { |line_number| set.add(line_number) }
      end
    end
  end
end
