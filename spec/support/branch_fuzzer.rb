# frozen_string_literal: true

require "prism"

module BranchFuzzer
  extend self

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

  class Generator
    LEAVES = ["a", "b", "c", "1", ":x", "foo", "a.b", "self"].freeze
    CONDITIONS = ["a", "b", "c", "foo", "a.b", "a && b", "a || b"].freeze
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
