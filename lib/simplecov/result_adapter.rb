# frozen_string_literal: true

require "coverage"

module SimpleCov
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
    # array; everything since uses the `{lines:, branches:, methods:}` shape.
    def adapt_one(file_name, cover_statistic)
      return {"lines" => cover_statistic} if cover_statistic.instance_of?(Array)

      adapt_oneshot_lines_if_needed(file_name, cover_statistic)
      normalize_method_keys(cover_statistic)
      aggregate_duplicated_branches(cover_statistic)
      cover_statistic
    end

    # Normalizes memory addresses in method coverage keys so results from
    # different processes can be merged: anonymous class names like
    # "#<Class:0x00007ff19ab24790>" get inconsistent addresses across runs, and
    # address widths vary by runtime.
    ADDRESS_PATTERN = /0x\h+/
    private_constant :ADDRESS_PATTERN

    ADDRESS_PLACEHOLDER = "0x0"
    private_constant :ADDRESS_PLACEHOLDER

    # Strips the `#<Class:Foo>` wrapper Ruby's Coverage adds to singleton-class
    # method keys. `module_function` and class methods get recorded both as
    # singleton and instance/module entries pointing at the same source
    # location, and only one of the two is ever reachable at runtime. Only
    # named constants: anonymous-class addresses are left to ADDRESS_PATTERN.
    SINGLETON_WRAPPER_PATTERN = /\A#<Class:([A-Z_][\w:]*)>\z/
    private_constant :SINGLETON_WRAPPER_PATTERN

    # Ruby's method coverage records one entry per defined method, not per
    # source location: a block handed to `define_method` from a shared code
    # path yields a separate `[receiver, name, location]` entry for every class
    # it's defined on and every name it's defined under, all pointing at the
    # same source. A file-based report can only express "was the method at this
    # location ever executed", so entries are aggregated by location alone,
    # summing hits. Otherwise each generated copy that never ran shows as a
    # phantom uncovered method on a line whose line coverage is 100% (#1234).
    # The first entry's normalized key is kept for display.
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
      receiver, *rest = key
      normalized_receiver = class_display_name(receiver)
                            .gsub(ADDRESS_PATTERN, ADDRESS_PLACEHOLDER)
                            .sub(SINGLETON_WRAPPER_PATTERN, '\1')
      [normalized_receiver, *rest]
    end

    # Rendering a class name can execute user code: a singleton class's `to_s`
    # renders its attached object via `#inspect`, which a module can shadow
    # with an incompatible signature (Liquid::Utils defines
    # `inspect(value, max_depth = 2)` as a module_function, so rendering
    # `#<Class:Liquid::Utils>` raises ArgumentError). A coverage report must
    # never crash the host suite over that (#1236).
    def class_display_name(klass)
      klass.to_s
    rescue StandardError
      singleton_wrapper_name(klass) || Object.instance_method(:to_s).bind_call(klass)
    end

    # `singleton_class?` is a Module method, so a receiver that is neither a
    # class nor a module has to be turned away first. Anything that then
    # answers `singleton_class?` truthily is a Class, so `attached_object`
    # applies, reached through a bound method so shadowing cannot divert it.
    def singleton_wrapper_name(klass)
      return nil unless klass.is_a?(Module) && klass.singleton_class?

      attached = Class.instance_method(:attached_object).bind_call(klass)
      name = Module.instance_method(:name).bind_call(attached) if attached.is_a?(Module)
      name && "#<Class:#{name}>"
    end

    # Ruby's eval coverage records a fresh set of branch entries for every
    # compile of an eval'd string: a template rendered through multiple view
    # classes yields several `[:if, id, location]` conditions at identical
    # coordinates, each counting only the renders that flowed through that
    # compile. Reported as-is they inflate the branch denominator and turn a
    # side covered under a different compile into a phantom miss (#1235).
    # Absorbing into an empty table dedups, since BranchesCombiner keys arms on
    # location identity. Regular source can never produce two conditions at the
    # same location, so this is a no-op outside eval.
    def aggregate_duplicated_branches(cover_statistic)
      branches = cover_statistic[:branches]
      return unless branches

      combiner = Combine::BranchesCombiner
      cover_statistic[:branches] = combiner.materialize(combiner.absorb({}, branches))
    end

    def adapt_oneshot_lines_if_needed(file_name, cover_statistic)
      return unless cover_statistic.key?(:oneshot_lines)

      oneshot_lines = cover_statistic.delete(:oneshot_lines)
      line_stub     = build_line_stub(file_name)
      oneshot_lines.each { |covered_line| line_stub[covered_line - 1] = 1 }
      cover_statistic[:lines] = line_stub
    end

    # A file that has vanished or no longer parses has no stub to build from, so
    # start from nothing: the assignments in `adapt_oneshot_lines_if_needed`
    # grow the array to the highest covered line, which is as far as the
    # oneshot data reaches anyway.
    def build_line_stub(file_name)
      Coverage.line_stub(file_name)
    rescue Errno::ENOENT, SyntaxError
      []
    end
  end
end
