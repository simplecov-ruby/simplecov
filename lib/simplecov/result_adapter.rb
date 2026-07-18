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
    # shape. Newer entries also need their methods and branches tables
    # massaged before downstream code reports or merges them.
    def adapt_one(file_name, cover_statistic)
      return {"lines" => cover_statistic} if cover_statistic.is_a?(Array)

      adapt_oneshot_lines_if_needed(file_name, cover_statistic)
      normalize_method_keys(cover_statistic)
      aggregate_duplicated_branches(cover_statistic)
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

    # Ruby's method coverage records one entry per DEFINED METHOD, not per
    # source location: a block handed to `define_method` /
    # `define_singleton_method` from a shared code path yields a separate
    # `[receiver, name, location]` entry for every class it's defined on
    # (a module's `included` hook defining onto each descendant) AND for
    # every name it's defined under (a builder looping `define_method key`
    # over a container), all pointing at the same source. A file-based
    # report can only express "was the method at this location ever
    # executed", so entries are aggregated by location alone, summing
    # hits — otherwise each receiver or name whose generated copy never
    # ran shows as a phantom uncovered method on a line whose line
    # coverage is 100%. Regular `def`s map one location to one name, so
    # they are unaffected. The first entry's (normalized) key is kept for
    # display. See issue #1234.
    def normalize_method_keys(cover_statistic)
      methods = cover_statistic[:methods]
      return unless methods

      aggregated = {} #: Hash[untyped, [untyped, Integer]]
      methods.each_with_object(aggregated) do |(key, count), memo|
        location = key[2..] #: Array[untyped]
        retained_key, existing = memo[location] || [normalize_method_key(key), 0]
        memo[location] = [retained_key, existing + count]
      end
      cover_statistic[:methods] = aggregated.values.to_h
    end

    def normalize_method_key(key)
      normalized_key = key.dup
      normalized_key[0] = class_display_name(key[0])
                          .gsub(ADDRESS_PATTERN, ADDRESS_PLACEHOLDER)
                          .sub(SINGLETON_WRAPPER_PATTERN, '\1')
      normalized_key
    end

    # Rendering a class name can execute user code: a singleton class's
    # `to_s` renders its attached object via `#inspect`, which a module can
    # shadow with an incompatible signature (Liquid::Utils defines
    # `inspect(value, max_depth = 2)` as a module_function, so rendering
    # `#<Class:Liquid::Utils>` raises ArgumentError). A coverage report
    # must never crash the host suite over that, so on failure rebuild the
    # singleton wrapper from `Module#name` via bound methods (which cannot
    # be shadowed), falling back to the address form, which
    # ADDRESS_PATTERN then normalizes. See issue #1236.
    def class_display_name(klass)
      klass.to_s
    rescue StandardError
      singleton_wrapper_name(klass) || Object.instance_method(:to_s).bind_call(klass)
    end

    def singleton_wrapper_name(klass)
      return nil unless klass.is_a?(Class) && klass.singleton_class?

      attached = klass.attached_object
      # simplecov:disable branch — CRuby only reaches the rescue via a
      # Module/Class attached object (instance singletons render from the
      # class name chain without calling user inspect), so the non-Module
      # arm is defensive.
      name = Module.instance_method(:name).bind_call(attached) if attached.is_a?(Module)
      # simplecov:enable branch
      name && "#<Class:#{name}>"
    end

    # Ruby's eval coverage records a fresh set of branch entries for every
    # COMPILE of an eval'd string: a template rendered through multiple view
    # classes (e.g. hanami-view compiles each template once per view) yields
    # several `[:if, id, location]` conditions at identical coordinates in
    # the same file, each counting only the renders that flowed through that
    # compile. Reported as-is they inflate the branch denominator and turn a
    # side covered under a different compile into a phantom miss (issue
    # #1235). Aggregate them by (type, location) — combining a branches hash
    # with an empty one dedups within it, since BranchesCombiner keys arms
    # on location identity. Regular (non-eval) source can never produce two
    # conditions at the same location, so this is a no-op outside eval.
    def aggregate_duplicated_branches(cover_statistic)
      branches = cover_statistic[:branches]
      return unless branches

      cover_statistic[:branches] = Combine::BranchesCombiner.combine(branches, {})
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
