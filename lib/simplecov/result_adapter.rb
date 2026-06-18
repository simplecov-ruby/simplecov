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

    def self.call(*)
      new(*).adapt
    end

    def adapt
      return unless result

      result.to_h do |file_name, cover_statistic|
        [file_name, adapt_one(file_name, cover_statistic)]
      end
    end

  private

    # Pre-0.18 resultsets pointed each filename straight at a line-coverage
    # array; everything since uses the `{lines:, branches:, methods:}`
    # shape. Newer entries also need their methods table massaged before
    # downstream code merges across processes.
    def adapt_one(file_name, cover_statistic)
      return {"lines" => cover_statistic} if cover_statistic.is_a?(Array)

      adapt_oneshot_lines_if_needed(file_name, cover_statistic)
      normalize_method_keys(cover_statistic)
      cover_statistic
    end

    # Normalize memory addresses in method coverage keys so that results
    # from different processes can be merged. Anonymous class names like
    # "#<Class:0x00007ff19ab24790>" get inconsistent addresses across runs.
    # Address widths vary by runtime (32-bit hosts: 8 hex chars; 64-bit
    # CRuby: 16; some JVM/TruffleRuby formats may differ), so match any
    # length of hex digits and collapse to a single placeholder.
    ADDRESS_PATTERN = /0x\h+/
    private_constant :ADDRESS_PATTERN

    ADDRESS_PLACEHOLDER = "0x0"
    private_constant :ADDRESS_PLACEHOLDER

    # Strip the `#<Class:Foo>` wrapper Ruby's Coverage adds to singleton-class
    # method keys. `module_function` and class methods get recorded both as
    # singleton (`[#<Class:Foo>, :m, …]`) and instance/module (`[Foo, :m, …]`)
    # entries pointing at the same source location; only one of the two is
    # ever reachable at runtime, so we merge them. Only applies to named
    # constants — anonymous-class addresses like `#<Class:0x0>` are left
    # alone (handled by ADDRESS_PATTERN above).
    SINGLETON_WRAPPER_PATTERN = /\A#<Class:([A-Z_][\w:]*)>\z/
    private_constant :SINGLETON_WRAPPER_PATTERN

    def normalize_method_keys(cover_statistic)
      methods = cover_statistic[:methods]
      return unless methods

      cover_statistic[:methods] = methods.each_with_object({}) do |(key, count), normalized|
        normalized_key = key.dup
        normalized_key[0] = key[0].to_s
                                  .gsub(ADDRESS_PATTERN, ADDRESS_PLACEHOLDER)
                                  .sub(SINGLETON_WRAPPER_PATTERN, '\1')
        # Keys may collide after normalization (anonymous classes sharing a
        # method name, or singleton + instance forms of a module_function method).
        normalized[normalized_key] = normalized.fetch(normalized_key, 0) + count
      end
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
