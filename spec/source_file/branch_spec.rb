# frozen_string_literal: true

# rubocop:disable Style/HashSyntax

require "helper"

describe SimpleCov::SourceFile::Branch do
  let(:positive_branch) do
    described_class.new(start_line: 1, coverage: 0, inline: false, positive: true)
  end

  let(:negative_branch) do
    described_class.new(start_line: 1, coverage: 0, inline: false, positive: false)
  end

  context "a source branch if..else" do
    it "has positive badge of positive branch" do
      expect(positive_branch.badge).to eq "+"
    end

    it "has negative badge of negative branch" do
      expect(negative_branch.badge).to eq "-"
    end

    it "corrects report branch report" do
      expect(positive_branch.report).to eq([0, "+"])
      expect(negative_branch.report).to eq([0, "-"])
    end
  end

  context "A source branch with coverage" do
    let(:covered_branch) do
      described_class.new(start_line: 1, coverage: 1, inline: false, positive: true)
    end

    it "is covered" do
      expect(covered_branch).to be_covered
    end

    it "is not missed" do
      expect(covered_branch).not_to be_missed
    end
  end

  context "a source branch without coverage" do
    let(:uncovered_branch) do
      described_class.new(start_line: 1, coverage: 0, inline: false, positive: true)
    end

    it "isn't covered" do
      expect(uncovered_branch).not_to be_covered
    end

    it "is missed" do
      expect(uncovered_branch).to be_missed
    end
  end
end
# rubocop:enable Style/HashSyntax
