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

  # gotta check the validity of case shenaningans and probably move this test around
  xcontext "A source branch case..when..else" do
    let(:case_branch) do
      described_class.new(*([:case, 0, 1, 4, 10, 4] + [nil]))
    end

    let(:branches_without_else) do
      [
        case_branch,
        described_class.new(*([:when, 1, 2, 6, 8, 4] + [0])),
        described_class.new(*([:when, 2, 3, 8, 10, 4] + [0])),
        described_class.new(*([:else, 0, 1, 4, 10, 4] + [0]))
      ]
    end

    let(:branches_with_else) do
      [
        case_branch,
        described_class.new(*([:when, 1, 2, 6, 8, 4] + [0])),
        described_class.new(*([:when, 2, 3, 8, 10, 4] + [0])),
        described_class.new(*([:else, 3, 4, 10, 12, 4] + [0]))
      ]
    end

    it "returns positive badge for :when" do
      expect(branches_without_else[1].badge.to_sym).to eq(:+)
    end

    it "has right `case` sub branches which having else inside" do
      expect(case_branch.branches(branches_with_else).count).to eq(3)
      expect(case_branch.branches(branches_with_else).map(&:type)).to eq(%i[when when else])
    end

    it "has right `case` sub branches which does not have else inside" do
      expect(case_branch.branches(branches_without_else).count).to eq(2)
      expect(case_branch.branches(branches_without_else).map(&:type)).to eq(%i[when when])
    end

    it "has correct branch report (`when` always positive)" do
      expect(branches_without_else[1].report).to eq([0, "+"])
      expect(branches_without_else[2].report).to eq([0, "+"])
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
