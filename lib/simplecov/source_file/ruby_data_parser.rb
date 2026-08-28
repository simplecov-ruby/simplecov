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
      extend self

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
      # count, so a permanent cache stays small. Cached arrays are frozen
      # element-wise (String class names included, not just the tuple):
      # every caller destructures without mutating, and sharing one array
      # across callers must stay that way. The cache key needs no such
      # care — `Hash#[]=` dups and freezes String keys on its own.
      def call(structure)
        return structure if structure.is_a?(Array)

        parse_cache[structure] ||= parse_array_string(structure).each(&:freeze).freeze
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
        # Ripper wraps what it parsed in a `:program` node holding the
        # statements, and this input is supposed to be one array literal
        # and nothing else. Both passes answer nil for input Ruby can't
        # parse at all, so there may be no statement to unwrap at all.
        # Symbols are interned, so identity is the whole of the question.
        _program, statements = sexp
        first_statement, *extra = statements
        array_node = Array(first_statement)
        unless extra.empty? && array_node.first.equal?(:array)
          raise ArgumentError, "expected array literal: #{str.inspect}"
        end

        Array(array_node.fetch(1)).map { |element| parse_element(element) }
      end

      # Each `when` already knows the node's shape, so the elements read
      # straight out of it rather than through a second dispatch. A
      # symbol's text sits where a string's does, one node deeper.
      def parse_element(node)
        case node.fetch(0)
        when :@int                         then Integer(node.fetch(1))
        when :unary                        then -Integer(node.fetch(2).fetch(1)) # `-2`
        when :symbol_literal, :dyna_symbol then literal_text(node).to_sym
        when :string_literal               then literal_text(node)
        when :var_ref                      then node.fetch(1).fetch(1) # `Foo`
        when :const_path_ref               then const_path(node) # `Foo::Bar`
        else
          raise ArgumentError, "unexpected element: #{node}"
        end
      end

      # A constant path's namespace is an element in its own right, so
      # `Foo::Bar::Baz` comes back together one segment at a time.
      def const_path(node)
        "#{parse_element(node.fetch(1))}::#{node.fetch(2).fetch(1)}"
      end

      # The text a string or symbol literal carries. Ripper may emit
      # zero, one, or many fragments under it depending on the literal,
      # and the escapes it leaves in the source text come back out.
      def literal_text(node)
        unescape_ruby(node.fetch(1)[1..].map { |fragment| fragment.fetch(1) }.join)
      end

      # Undo the same backslash-prefix escapes the previous hand-rolled
      # parser undid: `\X` → `X` for any X.
      def unescape_ruby(raw)
        raw.gsub(/\\(.)/) { Regexp.last_match(1) }
      end

      # Method coverage keys can contain inspect-format class references
      # like `#<Class:Foo>` or `#<Class:0x...>`, which aren't valid Ruby
      # syntax. Wrap them in quotes so Ripper can parse the surrounding
      # array literal; downstream we treat them as opaque strings. The
      # pattern recurses because singleton methods on instances nest one
      # inspect segment inside another (`#<Class:#<Object:0x...>>`), and
      # stopping at the first `>` leaves a dangling `>` that fails both
      # Ripper passes and crashes the merge.
      def quote_inspected_class_segments(str)
        str.gsub(/#<(?:[^<>]|\g<0>)+>/) { |segment| %("#{segment.gsub('"', '\\"')}") }
      end
    end
  end
end
