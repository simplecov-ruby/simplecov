# frozen_string_literal: true

require "helper"
require "open3"

RSpec.describe "mutation sharding", mutant: false do
  def partition_script(count, total)
    <<~RUBY
      load "./Rakefile"
      subjects = (1..#{count}).map { |number| "S\#{number}" }
      shards = (0...#{total}).map { |index| mutant_shard(subjects, index, #{total}) }
      puts shards.map(&:size).inspect
      puts shards.flatten.sort.inspect
      puts subjects.sort.inspect
    RUBY
  end

  def shard_sizes_and_union(count, total)
    stdout, stderr, status =
      Open3.capture3("bundle", "exec", "ruby", "-rrake", "-e", partition_script(count, total),
                     chdir: SimpleCov.root.to_s)
    raise "the Rakefile helper failed: #{stderr}" unless status.success?

    stdout.lines.map { |line| eval(line) } # rubocop:disable Security/Eval
  end

  it "hands every subject to exactly one shard" do
    _sizes, union, subjects = shard_sizes_and_union(17, 4)

    expect(union).to eq(subjects)
  end

  it "keeps the shards within one subject of each other" do
    sizes, = shard_sizes_and_union(17, 4)

    expect(sizes.max - sizes.min).to be <= 1
  end

  it "leaves later shards empty rather than dropping subjects when there are fewer than shards" do
    sizes, union, subjects = shard_sizes_and_union(2, 4)

    expect(sizes).to eq([1, 1, 0, 0])
    expect(union).to eq(subjects)
  end
end
