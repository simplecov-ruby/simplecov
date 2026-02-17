# frozen_string_literal: true

module SimpleCov
  #
  # Responsible for adapting the format of the coverage result whether it's default or with statistics
  #
  class ResultAdapter
    attr_reader :result

    def initialize(result)
      @result = result
    end

    def self.call(*args)
      new(*args).adapt
    end

    def adapt
      return unless result

      result.each_with_object({}) do |(file_name, cover_statistic), adapted_result|
        if cover_statistic.is_a?(Array)
          adapted_result.merge!(file_name => {"lines" => cover_statistic})
        else
          adapt_oneshot_lines_if_needed(file_name, cover_statistic)
          adapted_result.merge!(file_name => cover_statistic)
        end
      end
    end

  private

    def adapt_oneshot_lines_if_needed(file_name, cover_statistic)
      if cover_statistic.key?(:oneshot_lines)
        line_stub = Coverage.line_stub(file_name)
        oneshot_lines = cover_statistic.delete(:oneshot_lines)
        oneshot_lines.each do |covered_line|
          line_stub[covered_line - 1] = 1
        end
        cover_statistic[:lines] = line_stub
      else
        cover_statistic
      end
    end
  end
end
