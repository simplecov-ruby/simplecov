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
    # Address widths vary by runtime (32-bit hosts: 8 hex chars; 64-bit
    # CRuby: 16; some JVM/TruffleRuby formats may differ), so match any
    # length of hex digits and collapse to a single placeholder.
    ADDRESS_PATTERN = /0x\h+/.freeze
    private_constant :ADDRESS_PATTERN

    ADDRESS_PLACEHOLDER = "0x0"
    private_constant :ADDRESS_PLACEHOLDER

    def normalize_method_keys(cover_statistic)
      methods = cover_statistic[:methods]
      return unless methods

      normalized = {}
      methods.each do |key, count|
        normalized_key = key.dup
        normalized_key[0] = normalized_key[0].to_s.gsub(ADDRESS_PATTERN, ADDRESS_PLACEHOLDER)
        # Keys might collide after normalization (two anonymous classes with same method)
        normalized[normalized_key] = normalized.fetch(normalized_key, 0) + count
      end
      cover_statistic[:methods] = normalized
    end

    def adapt_oneshot_lines_if_needed(file_name, cover_statistic)
      return unless cover_statistic.key?(:oneshot_lines)

      oneshot_lines = cover_statistic.delete(:oneshot_lines)
      line_stub     = build_line_stub(file_name, oneshot_lines)
      oneshot_lines.each { |covered_line| line_stub[covered_line - 1] = 1 }
      cover_statistic[:lines] = line_stub
    end

    def build_line_stub(file_name, oneshot_lines)
      Coverage.line_stub(file_name)
    rescue Errno::ENOENT, SyntaxError
      Array.new(oneshot_lines.max || 0, nil)
    end
  end
end
