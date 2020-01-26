# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::CoverageData do
  describe ".new" do
    it "retains statistics and computes new ones" do
      data = described_class.new(covered: 4, missed: 6, total_strength: 14)

      expect(data.covered).to eq 4
      expect(data.missed).to eq 6

      expect(data.total).to eq 10
      expect(data.percent).to eq 40.0
      expect(data.strength).to eq 1.4
    end

    it "can omit the total strength defaulting to 0.0" do
      data = described_class.new(covered: 4, missed: 6, total_strength: 0.0)

      expect(data.strength).to eq 0.0
    end

    it "can deal with it if everything is 0" do
      data = described_class.new(covered: 0, missed: 0, total_strength: 0.0)

      expect_all_empty(data)
    end
  end

  describe ".from" do
    it "returns an all 0s coverage data if there is no data" do
      data = described_class.from([])

      expect_all_empty(data)
    end

    it "returns all empty data when initialized with a couple of empty results" do
      data = described_class.from([empty_data, empty_data])

      expect_all_empty(data)
    end

    it "produces sensible total results" do
      data = described_class.from(
        [
          described_class.new(covered: 3, missed: 4, total_strength: 54),
          described_class.new(covered: 0, missed: 13, total_strength: 0),
          described_class.new(covered: 37, missed: 0, total_strength: 682)
        ]
      )

      expect(data.covered).to eq 40
      expect(data.missed).to eq 17
      expect(data.total).to eq 57
      expect(data.percent).to be_within(0.01).of(70.18)
      expect(data.strength).to be_within(0.01).of(12.91)
    end
  end

  def empty_data
    described_class.new(covered: 0, missed: 0, total_strength: 0.0)
  end

  def expect_all_empty(data)
    expect(data.covered).to eq 0
    expect(data.missed).to eq 0

    expect(data.total).to eq 0
    # might be counter intuitive but think of it as "we covered everything we could"
    expect(data.percent).to eq 100.0
    expect(data.strength).to eq 0.0
  end
end
