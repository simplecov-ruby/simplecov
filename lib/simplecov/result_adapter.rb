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
          normalize_method_keys(cover_statistic)
          adapted_result.merge!(file_name => cover_statistic)
        end
      end
    end

  private

    # Normalize memory addresses in method coverage keys so that results
    # from different processes can be merged. Anonymous class names like
    # "#<Class:0x00007ff19ab24790>" get inconsistent addresses across runs.
    def normalize_method_keys(cover_statistic)
      methods = cover_statistic[:methods]
      return unless methods

      normalized = {}
      methods.each do |key, count|
        normalized_key = key.dup
        normalized_key[0] = normalized_key[0].to_s.gsub(/0x\h{16}/, "0x0000000000000000")
        # Keys might collide after normalization (two anonymous classes with same method)
        normalized[normalized_key] = normalized.fetch(normalized_key, 0) + count
      end
      cover_statistic[:methods] = normalized
    end

    def adapt_oneshot_lines_if_needed(file_name, cover_statistic)
      return unless cover_statistic.key?(:oneshot_lines)

      oneshot_lines = cover_statistic.delete(:oneshot_lines)
      line_stub = begin
        Coverage.line_stub(file_name)
      rescue Errno::ENOENT, SyntaxError
        Array.new(oneshot_lines.max || 0, nil)
      end
      oneshot_lines.each do |covered_line|
        line_stub[covered_line - 1] = 1
      end
      cover_statistic[:lines] = line_stub
    end
  end
end
