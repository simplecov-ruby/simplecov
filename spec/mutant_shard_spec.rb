# frozen_string_literal: true

require "helper"
require_relative "../tasks/mutant_shard"

RSpec.describe MutantShard do
  let(:subjects) { (1..17).map { |number| "S#{number}" } }

  def shards(subjects, total)
    (0...total).map { |index| described_class.shard(subjects, index, total) }
  end

  it "hands every subject to exactly one shard" do
    expect(shards(subjects, 4).flatten).to match_array(subjects)
  end

  it "keeps the shards within one subject of each other" do
    sizes = shards(subjects, 4).map(&:size)

    expect(sizes.max - sizes.min).to be <= 1
  end

  it "spreads neighbouring subjects across runners rather than clumping them" do
    expect(described_class.shard(subjects, 0, 4)).to eq(%w[S1 S5 S9 S13 S17])
  end

  it "leaves later shards empty rather than dropping subjects when there are fewer than shards" do
    expect(shards(%w[S1 S2], 4).map(&:size)).to eq([1, 1, 0, 0])
  end

  it "gives one shard everything" do
    expect(described_class.shard(subjects, 0, 1)).to eq(subjects)
  end

  describe ".subjects_since" do
    def stub_mutant(output, success: true)
      status = instance_double(Process::Status, success?: success)
      allow(Open3).to receive(:capture2).and_return([output, status])
    end

    it "reads the subjects mutant lists for the revision" do
      stub_mutant("SimpleCov::Foo#bar\nSimpleCov::Baz.qux\n")

      expect(described_class.subjects_since("origin/main")).to eq(["SimpleCov::Foo#bar", "SimpleCov::Baz.qux"])
      expect(Open3).to have_received(:capture2).with(
        "bundle", "exec", "mutant", "environment", "subject", "list", "--since", "origin/main"
      )
    end

    it "drops the summary line mutant ends the listing with" do
      stub_mutant("SimpleCov::Foo#bar\nSubjects in environment: 1\n")

      expect(described_class.subjects_since("main")).to eq(["SimpleCov::Foo#bar"])
    end

    it "answers nothing for a revision that touched no subject" do
      stub_mutant("Subjects in environment: 0\n")

      expect(described_class.subjects_since("main")).to be_empty
    end

    it "raises when mutant could not list them" do
      stub_mutant("", success: false)

      expect { described_class.subjects_since("bogus") }
        .to raise_error(RuntimeError, "mutant could not list the subjects touched since bogus")
    end
  end
end
