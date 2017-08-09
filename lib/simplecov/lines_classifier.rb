module SimpleCov
  class LinesClassifier
    RELEVANT = 0
    NOT_RELEVANT = nil

    WHITESPACE_LINE = /^\s*$/
    COMMENT_LINE = /^\s*#/
    WHITESPACE_OR_COMMENT_LINE = Regexp.union(WHITESPACE_LINE, COMMENT_LINE)

    def self.no_cov_line
      /^(\s*)#(\s*)(\:#{SimpleCov.nocov_token}\:)/
    end

    def classify(lines)
      skipping = false

      lines.map do |line|
        if line =~ self.class.no_cov_line
          skipping = !skipping
          NOT_RELEVANT
        elsif line =~ WHITESPACE_OR_COMMENT_LINE || skipping
          NOT_RELEVANT
        else
          RELEVANT
        end
      end
    end
  end
end
