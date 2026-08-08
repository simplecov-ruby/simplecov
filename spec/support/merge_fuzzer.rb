# frozen_string_literal: true

# Deterministic generator of small, adversarial resultset shard sets for
# spec/combine_differential_spec.rb. Each seed reproduces exactly, so a mismatch
# can be replayed and shrunk by hand.
#
# The cases it deliberately produces, since these are the ones the merge rules
# actually turn on and the ones a real-world fixture tends not to contain:
#
# - files missing from some shards entirely (the nil short-circuit in
#   the accumulator, which passes a coverage through verbatim)
# - entries with no positive line, i.e. simulated / never-loaded files, mixed
#   with executed ones for the same file (`reconcile_synthesized`, #1233)
# - the same source span carrying a different branch id in each shard (the
#   drift #1233 is about)
# - two keys in *one* entry sharing an identity, so grouping has to collapse
#   within an entry and not only across them
# - class and name varying over one method location (#1234)
# - keys in both array and `inspect`-string form, mixed within a shard
# - `branches` / `methods` keys absent, and line arrays of differing lengths
module MergeFuzzer
module_function

  # A small pool, so collisions and drift arise naturally rather than by
  # special-casing. Two `:if` spans differ only in end column, as in #1233.
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

  # Returns an array of shards, each a `{file => entry}` coverage hash.
  #
  # `saturate` puts every file in every shard with both criterion keys always
  # present, so no file is ever carried by one shard alone. The accumulator
  # hands such a file back verbatim, skipping identity collapse entirely, which
  # is a divergence in its own right rather than anything about how N results
  # combine - see the characterization example in the spec.
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

  # A stand-in entry for an absent file is inert: no branches or methods to
  # contribute, and an all-nil line array merges to nil.
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

  # Every file lands in at least one shard, but often not all of them.
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

  # A non-executed entry has no positive count, which is what makes its branch
  # and method tuples non-authoritative next to an executed entry.
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

  # The random id is the per-process counter that differs between shards for
  # the same source span.
  def key(rng, span)
    type, *rest = span
    serialize(rng, [type, rng.rand(0..9), *rest])
  end

  def method_key(rng)
    _type, *location = CONDITION_SPANS.sample(random: rng)
    serialize(rng, [CLASSES.sample(random: rng), NAMES.sample(random: rng), *location])
  end

  # Half of the keys go out in the `inspect` form a JSON round-trip produces.
  def serialize(rng, tuple)
    rng.rand < 0.5 ? tuple : tuple.inspect
  end
end
