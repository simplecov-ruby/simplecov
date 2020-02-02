# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::CoverageStatistics do
  describe ".new" do
    it "retains statistics and computes new ones" do
      statistics = described_class.new(covered: 4, missed: 6, total_strength: 14)

      expect(statistics.covered).to eq 4
      expect(statistics.missed).to eq 6

      expect(statistics.total).to eq 10
      expect(statistics.percent).to eq 40.0
      expect(statistics.strength).to eq 1.4
    end

    it "can omit the total strength defaulting to 0.0" do
      statistics = described_class.new(covered: 4, missed: 6)

      expect(statistics.strength).to eq 0.0
    end

    it "can deal with it if everything is 0" do
      statistics = described_class.new(covered: 0, missed: 0, total_strength: 0.0)

      expect_all_empty(statistics)
    end
  end

  describe ".from" do
    it "returns an all 0s coverage statistics if there are no statistics" do
      statistics = described_class.from([])

      expect_all_empty(statistics)
    end

    it "returns all empty statistics when initialized with a couple of empty results" do
      statistics = described_class.from([empty_statistics, empty_statistics])

      expect_all_empty(statistics)
    end

    it "produces sensible total results" do
      statistics = described_class.from(
        [
          described_class.new(covered: 3, missed: 4, total_strength: 54),
          described_class.new(covered: 0, missed: 13, total_strength: 0),
          described_class.new(covered: 37, missed: 0, total_strength: 682)
        ]
      )

      expect(statistics.covered).to eq 40
      expect(statistics.missed).to eq 17
      expect(statistics.total).to eq 57
      expect(statistics.percent).to be_within(0.01).of(70.18)
      expect(statistics.strength).to be_within(0.01).of(12.91)
    end
  end

  def empty_statistics
    described_class.new(covered: 0, missed: 0, total_strength: 0.0)
  end

  def expect_all_empty(statistics)
    expect(statistics.covered).to eq 0
    expect(statistics.missed).to eq 0

    expect(statistics.total).to eq 0
    # might be counter-intuitive but think of it as "we covered everything we could"
    expect(statistics.percent).to eq 100.0
    expect(statistics.strength).to eq 0.0
  end
end
