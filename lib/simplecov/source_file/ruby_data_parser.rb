# frozen_string_literal: true

require "ripper"

module SimpleCov
  class SourceFile
    # `Coverage.result` reports condition and method keys as Ruby
    # arrays. When the resultset is round-tripped through JSON those
    # array keys become their stringified inspect form, so this parser
    # walks the literal back into a real Array without using `eval` (see
    # #801). The grammar covers symbols, strings, integers, unary minus,
    # and constant paths — every shape Coverage ever emits.
    module RubyDataParser
    module_function

      # Tests use the real data structures (except for integration tests)
      # so no need to put them through here.
      #
      # String parses are memoized: `Combine::BranchesCombiner` and
      # `Combine::MethodsCombiner` derive a merge identity from every key of
      # both sides on every pairwise merge, so collating N resultsets parses
      # each key string N-1 times — and Ripper dominates the wall time of a
      # large collate.
      # Key strings repeat across folds and within report building, while the
      # set of unique keys is bounded by the project's branch and method
      # count, so a permanent cache stays small. Cached arrays are frozen:
      # every caller destructures without mutating, and sharing one array
      # across callers must stay that way.
      def call(structure)
        return structure if structure.is_a?(Array)

        string = structure.to_s
        parse_cache[string] ||= parse_array_string(string).freeze
      end

      def parse_cache
        @parse_cache ||= {} #: Hash[String, untyped]
      end

      # Parse a string like '[:if, 0, 3, 4, 3, 21]' or
      # '["ClassName", :method1, 2, 2, 5, 5]' back into a Ruby array.
      def parse_array_string(str)
        # Try plain Ripper first; only pre-quote `#<...>` inspect segments
        # if the input isn't already valid Ruby (otherwise we corrupt
        # `"#<Class:Foo>"` strings that *are* valid Ruby literals — exactly
        # the shape simplecov-on-simplecov method-coverage keys take).
        sexp = Ripper.sexp(str) || Ripper.sexp(quote_inspected_class_segments(str))
        # simplecov:disable — defensive: Ripper.sexp returning nil from both passes requires malformed input
        array_node = sexp&.dig(1, 0)
        # simplecov:enable
        raise ArgumentError, "expected array literal: #{str.inspect}" unless array_node && array_node[0] == :array

        Array(array_node[1]).map { |element| parse_element(element) }
      end

      def parse_element(node)
        case node[0]
        when :@int, :unary                 then parse_integer_node(node)
        when :symbol_literal, :dyna_symbol then parse_symbol_node(node)
        when :string_literal               then unescape_ruby(string_literal_text(node[1]))
        when :var_ref                      then node.dig(1, 1) # `Foo`
        when :const_path_ref               then "#{parse_element(node[1])}::#{node[2][1]}" # `Foo::Bar`
        else
          # simplecov:disable — defensive fallback for unexpected Ripper node shapes
          raise ArgumentError, "unexpected element: #{node.inspect}"
          # simplecov:enable
        end
      end

      def parse_integer_node(node)
        node[0] == :@int ? node[1].to_i : -node[2][1].to_i
      end

      def parse_symbol_node(node)
        if node[0] == :symbol_literal
          node.dig(1, 1, 1).to_sym
        else
          unescape_ruby(string_literal_text(node[1])).to_sym
        end
      end

      # Concatenate the text fragments of a `:string_content` node. Ripper
      # may emit zero, one, or many `:@tstring_content` children depending
      # on the literal.
      def string_literal_text(string_content)
        Array(string_content[1..]).map { |child| child[1] }.join
      end

      # Undo the same backslash-prefix escapes the previous hand-rolled
      # parser undid: `\X` → `X` for any X.
      def unescape_ruby(raw)
        raw.gsub(/\\(.)/) { ::Regexp.last_match(1) }
      end

      # Method coverage keys can contain inspect-format class references
      # like `#<Class:Foo>` or `#<Class:0x...>`, which aren't valid Ruby
      # syntax. Wrap them in quotes so Ripper can parse the surrounding
      # array literal; downstream we treat them as opaque strings.
      def quote_inspected_class_segments(str)
        str.gsub(/#<[^>]*>/) { |segment| %("#{segment.gsub('"', '\\"')}") }
      end
    end
  end
end
