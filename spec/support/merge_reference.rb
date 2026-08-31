# frozen_string_literal: true

module MergeReference
  extend self

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

  def contributing(entries)
    executed = entries.select { |entry| executed?(entry) }
    executed.empty? ? entries : executed
  end

  def executed?(entry)
    Array(entry["lines"]).any? { |count| count&.positive? }
  end

  def merge_lines(entries)
    arrays = entries.filter_map { |entry| entry["lines"] }
    return nil if arrays.empty?

    Array.new(arrays.map(&:size).max) { |index| merge_line(arrays, index) }
  end

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

  def sum_counts(pairs, &)
    group(pairs, &).to_h { |first_key, group| [first_key, group.sum { |(_key, count)| count }] }
  end

  def group(pairs)
    grouped = {}
    pairs.each do |pair|
      slot = grouped[yield(pair.first)] ||= [pair.first, []]
      slot[1] << pair
    end
    grouped.values
  end

  def span(key)
    tuple = tuple(key)
    [tuple[0], *tuple[2..5]]
  end

  def location(key)
    tuple(key)[2..5]
  end

  def tuple(key)
    key.is_a?(Array) ? key : SimpleCov::SourceFile::RubyDataParser.call(key)
  end
end
