# frozen_string_literal: true

# An independent statement of what merging N resultsets should produce, used as
# the oracle for spec/merge_differential_spec.rb.
#
# `ResultsCombiner` folds resultsets pairwise, which makes the rules it applies
# hard to read off the code. `reconcile_synthesized` especially: it is defined
# on a *pair*, and its N-way meaning only emerges from the fold. This module
# states the N-way rules directly, written for obviousness rather than speed.
#
# - Lines merge across every entry for a file: `nil` only where every entry is
#   `nil` (or ended earlier), otherwise the sum with `nil` read as 0. Lines are
#   never dropped, whatever `executed?` says (issue #1059).
# - Branches and methods come only from *executed* entries when any entry for
#   the file was executed, and from all entries otherwise. A simulated entry
#   synthesizes its tuples statically, so merging them into a real run's would
#   keep any drifted location as a phantom, permanently-missed branch (#1233).
# - Keys group by identity - location, ignoring the id, and ignoring class and
#   name for methods (#1233, #1234). Counts sum, and the first key seen among
#   the contributing entries is retained.
module MergeReference
module_function

  def call(shards, branches:, methods:)
    shards.flat_map(&:keys).uniq.to_h do |file|
      entries = shards.filter_map { |shard| shard[file] }
      [file, merge_entries(entries, branches: branches, methods: methods)]
    end
  end

  def merge_entries(entries, branches:, methods:)
    sources = contributing(entries)
    merged = {"lines" => merge_lines(entries)}
    merged["branches"] = merge_branches(sources) if branches
    merged["methods"] = merge_methods(sources) if methods
    merged
  end

  # The entries whose branch and method tuples are authoritative.
  def contributing(entries)
    executed = entries.select { |entry| executed?(entry) }
    executed.empty? ? entries : executed
  end

  # A file some process actually loaded has at least one executed line.
  def executed?(entry)
    Array(entry["lines"]).any? { |count| count&.positive? }
  end

  # Nil when no entry carried lines at all, matching the short-circuit in
  # `Combine.combine` for two absent coverages.
  def merge_lines(entries)
    arrays = entries.filter_map { |entry| entry["lines"] }
    return nil if arrays.empty?

    Array.new(arrays.map(&:size).max) { |index| merge_line(arrays, index) }
  end

  # A line stays `nil` only where every entry had `nil` there; a `0` on any
  # entry makes it relevant-but-uncovered rather than absent (issue #1059).
  def merge_line(arrays, index)
    counts = arrays.map { |array| array[index] }
    counts.all?(&:nil?) ? nil : counts.sum(&:to_i)
  end

  def merge_branches(entries)
    conditions = entries.flat_map { |entry| (entry["branches"] || {}).to_a }
    group(conditions) { |key| span(key) }.to_h do |first_key, pairs|
      arms = pairs.flat_map { |(_condition, table)| table.to_a }
      [first_key, sum_counts(arms) { |key| span(key) }]
    end
  end

  def merge_methods(entries)
    sum_counts(entries.flat_map { |entry| (entry["methods"] || {}).to_a }) { |key| location(key) }
  end

  def sum_counts(pairs, &identity)
    group(pairs, &identity).to_h { |first_key, group| [first_key, group.sum { |(_key, count)| count }] }
  end

  # Groups `[key, value]` pairs by their key's identity, as
  # `[[first_key_seen, [pair, ...]], ...]` in first-seen order.
  def group(pairs)
    grouped = {}
    pairs.each do |pair|
      slot = grouped[yield(pair.first)] ||= [pair.first, []]
      slot[1] << pair
    end
    grouped.values
  end

  # `[type, id, sl, sc, el, ec]` -> `[type, sl, sc, el, ec]`
  def span(key)
    tuple = tuple(key)
    [tuple[0], *tuple[2..5]]
  end

  # `[class, name, sl, sc, el, ec]` -> `[sl, sc, el, ec]`
  def location(key)
    tuple(key)[2..5]
  end

  # Keys are arrays in-process and their `inspect` form once a resultset has
  # been through JSON; both must resolve to the same identity.
  def tuple(key)
    key.is_a?(Array) ? key : SimpleCov::SourceFile::RubyDataParser.call(key)
  end
end
