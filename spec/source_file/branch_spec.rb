# frozen_string_literal: true

require "helper"

describe SimpleCov::SourceFile::Branch do
  let(:if_branch) do
    described_class.new(start_line: 1, end_line: 3, coverage: 0, inline: false, type: :then)
  end

  let(:else_branch) do
    described_class.new(start_line: 1, end_line: 3, coverage: 0, inline: false, type: :else)
  end

  context "a source branch if..else" do
    it "correct branch report" do
      expect(if_branch.report).to eq([:then, 0])
      expect(else_branch.report).to eq([:else, 0])
    end
  end

  context "A source branch with coverage" do
    let(:covered_branch) do
      described_class.new(start_line: 1, end_line: 3, coverage: 1, inline: false, type: :then)
    end

    it "is covered" do
      expect(covered_branch).to be_covered
    end

    it "is neither covered not missed if skipped" do
      covered_branch.skipped!
      expect(covered_branch).not_to be_covered
      expect(covered_branch).not_to be_missed
    end

    it "is not missed" do
      expect(covered_branch).not_to be_missed
    end
  end

  context "a source branch without coverage" do
    let(:uncovered_branch) do
      described_class.new(start_line: 1, end_line: 3, coverage: 0, inline: false, type: :then)
    end

    it "isn't covered" do
      expect(uncovered_branch).not_to be_covered
    end

    it "is missed" do
      expect(uncovered_branch).to be_missed
    end

    it "is neither covered not missed if skipped" do
      uncovered_branch.skipped!
      expect(uncovered_branch).not_to be_covered
      expect(uncovered_branch).not_to be_missed
    end
  end

  describe "skipping lines" do
    subject { described_class.new(start_line: 5, end_line: 7, coverage: 0, inline: false, type: :then) }

    it "isn't skipped by default" do
      expect(subject).not_to be_skipped
    end

    it "can be skipped" do
      subject.skipped!
      expect(subject).to be_skipped
    end
  end

  describe "#overlaps_with?(range)" do
    subject { described_class.new(start_line: 5, end_line: 7, coverage: 0, inline: false, type: :then) }

    it "doesn't overlap with a range beyond its lines" do
      expect(subject.overlaps_with?(8..10)).to eq false
    end

    it "doesn't overlap with a range before its lines" do
      expect(subject.overlaps_with?(3..4)).to eq false
    end

    it "overlaps with a range that fully includes everything" do
      expect(subject.overlaps_with?(1..100)).to eq true
    end

    it "overlaps with a range that exactly includes it" do
      expect(subject.overlaps_with?(5..7)).to eq true
    end

    it "overlaps with a range that partially includes its beginning" do
      expect(subject.overlaps_with?(1..5)).to eq true
    end

    it "overlaps with a range that partially includes its end" do
      expect(subject.overlaps_with?(7..10)).to eq true
    end

    it "overlaps with a range that pends in its middle" do
      expect(subject.overlaps_with?(1..6)).to eq true
    end
  end
end
