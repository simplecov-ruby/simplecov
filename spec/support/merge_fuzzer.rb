# frozen_string_literal: true

module MergeFuzzer
  extend self

  CONDITION_SPANS = [
    [:if, 2, 2, 4, 10], [:if, 2, 2, 4, 12], [:unless, 6, 4, 8, 20],
    [:"&.", 9, 2, 9, 18], [:case, 11, 2, 15, 8]
  ].freeze
  ARM_SPANS = [
    [:then, 3, 4, 3, 10], [:else, 4, 4, 4, 10], [:when, 12, 4, 12, 9], [:body, 7, 6, 7, 14]
  ].freeze
  CLASSES = ["Foo", "Bar", "#<Class:0x0>"].freeze
  NAMES = %i[call run inspect].freeze
  FILES = %w[a.rb b.rb c.rb d.rb].freeze

  def shards(seed, saturate: false)
    rng = Random.new(seed)
    count = rng.rand(2..5)
    files = FILES.first(rng.rand(1..FILES.size))
    membership = files.to_h { |file| [file, present_in(rng, count)] }
    built = Array.new(count) do |index|
      files.filter_map { |file| [file, entry(rng)] if membership[file].include?(index) }.to_h
    end
    saturate ? saturated(built) : built
  end

  def saturated(shards)
    files = shards.flat_map(&:keys).uniq
    shards.map do |shard|
      files.to_h do |file|
        entry = shard[file] || {"lines" => [nil]}
        [file, {"lines" => entry["lines"], "branches" => entry["branches"] || {},
                "methods" => entry["methods"] || {}}]
      end
    end
  end

  def present_in(rng, count)
    chosen = (0...count).select { rng.rand < 0.75 }
    chosen.empty? ? [rng.rand(count)] : chosen
  end

  def entry(rng)
    entry = {"lines" => lines(rng, executed: rng.rand < 0.6)}
    entry["branches"] = branches(rng) unless rng.rand < 0.2
    entry["methods"] = methods(rng) unless rng.rand < 0.2
    entry
  end

  def lines(rng, executed:)
    counts = Array.new(rng.rand(1..6)) { rng.rand < 0.4 ? nil : 0 }
    counts[rng.rand(counts.size)] = rng.rand(1..5) if executed
    counts
  end

  def branches(rng)
    Array.new(rng.rand(0..3)) do
      [key(rng, CONDITION_SPANS.sample(random: rng)), arms(rng)]
    end.to_h
  end

  def arms(rng)
    Array.new(rng.rand(1..3)) { [key(rng, ARM_SPANS.sample(random: rng)), rng.rand(0..4)] }.to_h
  end

  def methods(rng)
    Array.new(rng.rand(0..3)) { [method_key(rng), rng.rand(0..4)] }.to_h
  end

  def key(rng, span)
    type, *rest = span
    serialize(rng, [type, rng.rand(0..9), *rest])
  end

  def method_key(rng)
    _type, *location = CONDITION_SPANS.sample(random: rng)
    serialize(rng, [CLASSES.sample(random: rng), NAMES.sample(random: rng), *location])
  end

  def serialize(rng, tuple)
    rng.rand < 0.5 ? tuple : tuple.inspect
  end
end
