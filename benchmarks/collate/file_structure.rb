# frozen_string_literal: true

require_relative "distribution"
require_relative "shape"

module CollateBenchmark
  class FileStructure
    Entry = Struct.new(:relative_path, :lines, :branches, keyword_init: true)

    TOP_LEVEL_DIRS = {
      "app/models" => 22, "app/services" => 18, "app/controllers" => 12, "app/jobs" => 8,
      "app/serializers" => 6, "app/policies" => 4, "lib" => 20, "config/initializers" => 4,
      "app/helpers" => 3, "app/mailers" => 3
    }.freeze

    NOUNS = %w[account widget invoice session token report device policy alert channel
               profile schedule payment contact endpoint record digest bundle roster
               ledger transfer webhook receipt cursor snapshot boundary segment].freeze
    QUALIFIERS = %w[legacy internal external primary shared cached pending archived
                    inbound outbound derived nested scoped].freeze

    def initialize(scale:, seed:)
      @scale = scale
      @rng = Random.new(seed)
    end

    def call
      sizes = line_counts
      conditions = condition_counts(sizes)

      paths(sizes.size).each_with_index.map do |path, index|
        lines = build_lines(sizes[index])
        Entry.new(relative_path: path, lines: lines, branches: build_branches(lines, conditions[index]))
      end
    end

  private

    def line_counts
      Distribution.samples(
        Shape::LINES_PER_FILE, Shape.files(@scale),
        total: Shape.lines(@scale), floor: 3
      ).shuffle(random: @rng)
    end

    def condition_counts(sizes)
      branchy = branchy_indices(sizes.size)
      counts = Distribution.samples(
        Shape::CONDITIONS_PER_BRANCHY_FILE, branchy.size,
        total: Shape.conditions(@scale), floor: 1
      )

      assigned = Array.new(sizes.size, 0)
      branchy.sort_by { |index| sizes[index] }.each_with_index { |index, rank| assigned[index] = counts[rank] }
      assigned
    end

    def branchy_indices(count)
      (0...count).to_a.sample((count * Shape::BRANCHY_FILE_FRACTION).round, random: @rng)
    end

    def paths(count)
      Array.new(count) do |index|
        segments = [Distribution.weighted_choice(TOP_LEVEL_DIRS, @rng)]
        segments << NOUNS.sample(random: @rng) if @rng.rand < 0.45
        segments << QUALIFIERS.sample(random: @rng) if @rng.rand < 0.15
        segments << "#{QUALIFIERS.sample(random: @rng)}_#{NOUNS.sample(random: @rng)}_#{index}.rb"
        segments.join("/")
      end
    end

    def build_lines(size)
      Array.new(size) do
        next nil if @rng.rand >= Shape::RELEVANT_LINE_FRACTION

        @rng.rand < Shape::COVERED_RELEVANT_FRACTION ? hit_count : 0
      end
    end

    def hit_count
      ceiling = Distribution.weighted_choice(Shape::HIT_COUNT_TAIL, @rng)
      ceiling == 1 ? 1 : @rng.rand(2..ceiling)
    end

    def build_branches(lines, conditions)
      return {} if conditions.zero?

      ids = (0..).each
      conditions.times.each_with_object({}) do |_, table|
        add_condition(table, lines.size, ids)
      end
    end

    def add_condition(table, max_line, ids)
      arms = Distribution.weighted_choice(Shape::ARMS_PER_CONDITION, @rng)
      condition_type, arm_types = classify_condition(arms)
      start_line = @rng.rand(1..max_line)

      table[tuple_key(condition_type, ids.next, start_line, max_line)] =
        arm_types.to_h { |arm_type| [tuple_key(arm_type, ids.next, start_line, max_line), arm_hit_count] }
    end

    def classify_condition(arms)
      case arms
      when 1 then [Distribution.weighted_choice(Shape::LOOP_CONDITION_TYPES, @rng), [:body]]
      when 2 then two_arm_condition
      else [:case, Array.new(arms - 1) { arm_type } << :else]
      end
    end

    def two_arm_condition
      type = Distribution.weighted_choice(Shape::TWO_ARM_CONDITION_TYPES, @rng)
      [type, [type == :case ? arm_type : :then, :else]]
    end

    def arm_type
      @rng.rand < Shape::PATTERN_MATCH_FRACTION ? :in : :when
    end

    def arm_hit_count
      @rng.rand < Shape::ZERO_HIT_ARM_FRACTION ? 0 : hit_count
    end

    def tuple_key(type, id, start_line, max_line)
      end_line = [start_line + @rng.rand(0..3), max_line].min
      start_col = @rng.rand(2..40)
      [type, id, start_line, start_col, end_line, start_col + @rng.rand(4..60)].inspect
    end
  end
end
