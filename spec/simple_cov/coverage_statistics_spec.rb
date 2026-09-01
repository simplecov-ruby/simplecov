# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::CoverageStatistics do
  describe ".new" do
    it "retains the counts it was given" do
      statistics = described_class.new(covered: 4, missed: 6, omitted: 2, total_strength: 14)

      expect(statistics).to have_attributes(covered: 4, missed: 6, omitted: 2)
    end

    it "computes the statistics that follow from them" do
      statistics = described_class.new(covered: 4, missed: 6, omitted: 2, total_strength: 14)

      expect(statistics).to have_attributes(total: 10, percent: 40.0, strength: 1.4)
    end

    it "defaults omitted to exactly the Integer zero" do
      statistics = described_class.new(covered: 4, missed: 6)

      expect(statistics.omitted).to be 0
    end

    it "defaults the total strength to nothing, and still answers a Float" do
      statistics = described_class.new(covered: 4, missed: 6)

      expect(statistics.strength).to be 0.0
    end

    it "answers a Float strength for an Integer total strength" do
      statistics = described_class.new(covered: 4, missed: 6, total_strength: 14)

      expect(statistics.strength).to be 1.4
    end

    it "keeps a percent it was handed instead of computing one" do
      statistics = described_class.new(covered: 1, missed: 1, percent: 12.34)

      expect(statistics.percent).to be 12.34
    end

    it "can deal with it if everything is 0" do
      statistics = described_class.new(covered: 0, missed: 0, total_strength: 0.0)

      expect_all_empty(statistics)
    end
  end

  describe ".from" do
    let(:summed) do
      described_class.from(
        [
          described_class.new(covered: 3, missed: 4, omitted: 2, total_strength: 54),
          described_class.new(covered: 0, missed: 13, omitted: 5, total_strength: 0),
          described_class.new(covered: 37, missed: 0, omitted: 8, total_strength: 682)
        ]
      )
    end

    it "returns an all 0s coverage statistics if there are no statistics" do
      statistics = described_class.from([])

      expect_all_empty(statistics)
    end

    it "returns all empty statistics when initialized with a couple of empty results" do
      statistics = described_class.from([empty_statistics, empty_statistics])

      expect_all_empty(statistics)
    end

    it "sums the counts of everything it was given" do
      expect(summed).to have_attributes(covered: 40, missed: 17, omitted: 15, total: 57)
    end

    it "produces sensible total results" do
      expect(summed).to have_attributes(
        percent: a_value_within(0.01).of(70.18),
        strength: a_value_within(0.01).of(12.91)
      )
    end
  end

  def empty_statistics
    described_class.new(covered: 0, missed: 0, total_strength: 0.0)
  end

  def expect_all_empty(statistics)
    expect(statistics).to have_attributes(
      covered: 0,
      missed: 0,
      omitted: 0,
      total: 0,
      percent: 100.0,
      strength: 0.0
    )
  end

  describe "the percent it reports" do
    it "keeps a percent it was given" do
      expect(described_class.new(covered: 8, missed: 2, percent: 42.0).percent).to eq(42.0)
    end

    it "works one out from the counts when none was given" do
      expect(described_class.new(covered: 8, missed: 2).percent).to eq(80.0)
    end
  end

  it "starts from no strength when none was recorded" do
    expect(described_class.new(covered: 8, missed: 2).strength).to eq(0.0)
  end

  it "averages the recorded strength over the lines it covers" do
    expect(described_class.new(covered: 8, missed: 2, total_strength: 30.0).strength).to eq(3.0)
  end
end
