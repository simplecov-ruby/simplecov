# frozen_string_literal: true

require "prism"

# Deterministic generator of small `def fx` bodies that nest every branch
# construct Prism emits, for the differential fuzz spec. Each (seed, index)
# pair reproduces exactly, so a mismatch can be replayed. Only Prism-valid
# programs are returned; they are meant to be *loaded* (defining `fx`), never
# run, so undefined references in their bodies are fine.
module BranchFuzzer
module_function

  # Returns { "s<seed>_<index>" => source } for the requested volume, with
  # duplicate sources dropped.
  def programs(seeds:, per_seed:)
    seen = Set.new
    result = {}
    seeds.times { |seed| add_seed_programs(result, seen, seed, per_seed) }
    result
  end

  def add_seed_programs(result, seen, seed, per_seed)
    generator = Generator.new(Rng.new(seed + 1))
    per_seed.times do |index|
      source = generator.program
      next unless Prism.parse(source).success?
      next unless seen.add?(source)

      result["s#{seed}_#{index}"] = source
    end
  end

  # A tiny linear-congruential PRNG — seeded, portable, and reproducible.
  class Rng
    def initialize(seed)
      @state = ((seed * 2_654_435_761) + 1) & 0xFFFFFFFF
    end

    def int(max)
      @state = ((@state * 1_103_515_245) + 12_345) & 0x7FFFFFFF
      @state % max
    end

    def pick(array)
      array[int(array.length)]
    end

    def chance?(numerator, denominator)
      int(denominator) < numerator
    end
  end

  # Recursively builds a branch-construct-laden method body.
  class Generator
    # Value-position leaves (arm bodies): literals are fine here.
    LEAVES = ["a", "b", "c", "1", ":x", "foo", "a.b", "self"].freeze
    # Condition leaves: never constant, so the compiler can't fold the
    # branch away. Loops and case subjects always draw from here (they
    # don't fold, literal or not), as do one-line pattern subjects
    # (their legacy conventions are pinned deterministically instead).
    CONDITIONS = ["a", "b", "c", "foo", "a.b", "a && b", "a || b"].freeze
    # The if-like sites also draw compile-time literals, so the fuzzer
    # exercises constant folding and its dead-arm elimination — the
    # class where the phantom-tuple bugs actually lived. The
    # parenthesized and multi-statement forms exercise paren opacity and
    # the leading-statement elimination rules, which vary by Ruby
    # version.
    FOLDABLE_CONDITIONS = ["true", "false", "nil", "1", "(nil)",
                           "(1; 2)", "(foo; 2)", "(1; nil)", "(@x; 2)"].freeze
    PATTERNS = ["Integer", "String", "[a]", "{x:}", "Symbol"].freeze
    CONSTRUCTS = %i[
      gen_if gen_unless gen_ternary gen_case_when gen_case_in gen_while
      gen_until gen_do_while gen_safe_nav gen_modifier gen_oneline_pattern
    ].freeze

    def initialize(rng)
      @rng = rng
    end

    def program
      "def fx(a, b, c)\n#{statements(0)}\nend\n"
    end

  private

    def statements(depth)
      Array.new(1 + @rng.int(3)) { statement(depth) }.join("\n")
    end

    def statement(depth)
      return indent(depth, leaf) if depth >= 4 || @rng.chance?(1, 3)

      send(@rng.pick(CONSTRUCTS), depth)
    end

    def leaf
      @rng.pick(LEAVES)
    end

    def cond
      @rng.pick(CONDITIONS)
    end

    def foldable_cond
      @rng.chance?(1, 4) ? @rng.pick(FOLDABLE_CONDITIONS) : cond
    end

    def body_or_empty(depth)
      @rng.chance?(1, 4) ? "" : statements(depth + 1)
    end

    def gen_if(depth)
      parts = ["if #{foldable_cond}", body_or_empty(depth)]
      @rng.int(3).times { parts += ["elsif #{foldable_cond}", body_or_empty(depth)] }
      parts += ["else", body_or_empty(depth)] if @rng.chance?(1, 2)
      block(depth, parts << "end")
    end

    def gen_unless(depth)
      parts = ["unless #{foldable_cond}", body_or_empty(depth)]
      parts += ["else", body_or_empty(depth)] if @rng.chance?(1, 2)
      block(depth, parts << "end")
    end

    def gen_ternary(depth)
      indent(depth, "#{foldable_cond} ? #{leaf} : #{leaf}")
    end

    def gen_case_when(depth)
      parts = ["case #{cond}"]
      (1 + @rng.int(3)).times { parts += ["when #{leaf}", body_or_empty(depth)] }
      parts += ["else", body_or_empty(depth)] if @rng.chance?(1, 2)
      block(depth, parts << "end")
    end

    def gen_case_in(depth)
      parts = ["case #{cond}"]
      (1 + @rng.int(2)).times { parts += ["in #{@rng.pick(PATTERNS)}", body_or_empty(depth)] }
      parts += ["else", body_or_empty(depth)] if @rng.chance?(1, 2)
      block(depth, parts << "end")
    end

    def gen_while(depth)
      block(depth, ["while #{cond}", body_or_empty(depth), "end"])
    end

    def gen_until(depth)
      block(depth, ["until #{cond}", body_or_empty(depth), "end"])
    end

    def gen_do_while(depth)
      keyword = @rng.chance?(1, 2) ? "while" : "until"
      block(depth, ["begin", statements(depth + 1), "end #{keyword} #{cond}"])
    end

    def gen_safe_nav(depth)
      chain = "#{leaf}&.foo"
      chain += "(1)" if @rng.chance?(1, 2)
      chain += "&.bar" if @rng.chance?(1, 2)
      chain += " { |y| y }" if @rng.chance?(1, 2)
      indent(depth, chain)
    end

    def gen_modifier(depth)
      keyword = @rng.pick(%w[if unless while until])
      condition = %w[if unless].include?(keyword) ? foldable_cond : cond
      indent(depth, "#{leaf} #{keyword} #{condition}")
    end

    # Only the `=>` form: `x in Pattern` nested in a case/in body is a
    # Prism-vs-CRuby parser ambiguity, not an extractor concern.
    def gen_oneline_pattern(depth)
      indent(depth, "#{cond} => Integer")
    end

    def indent(depth, str)
      pad = "  " * (depth + 1)
      str.split("\n").map { |line| line.empty? ? line : pad + line }.join("\n")
    end

    def block(depth, parts)
      pad = "  " * (depth + 1)
      parts.flat_map { |part| part.split("\n") }.map { |line| line.empty? ? "" : pad + line }.join("\n")
    end
  end
end
