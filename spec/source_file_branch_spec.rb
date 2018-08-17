# frozen_string_literal: true

require "helper"

if SimpleCov.usable?
  describe SimpleCov::SourceFile::Branch do
    let(:results) do
      [[:if, 0, 1, 4, 10, 4],
       [:then, 1, 2, 6, 8, 4],
       [:else, 2, 2, 6, 8, 4],
       [:then, 1, 1, 6, 9, 5],
       [:else, 2, 1, 6, 8, 4]]
    end

    let(:root_branch) do
      SimpleCov::SourceFile::Branch.new(*(results[0] + [nil]))
    end

    let(:positive_sub_branch) do
      SimpleCov::SourceFile::Branch.new(*(results[1] + [0]))
    end

    let(:negative_sub_branch) do
      SimpleCov::SourceFile::Branch.new(*(results[2] + [0]))
    end

    let(:branches) do
      [root_branch, positive_sub_branch, negative_sub_branch]
    end

    let(:inline_branches) do
      [root_branch,
       SimpleCov::SourceFile::Branch.new(*(results[3] + [0])),
       SimpleCov::SourceFile::Branch.new(*(results[4] + [0]))]
    end

    context "A source branch if..else" do
      it "Is not root branch" do
        expect(root_branch.root?).to be true
      end

      it "Is a root branch" do
        expect(positive_sub_branch.root?).to be       false
        expect(negative_sub_branch.sub_branch?).to be true
      end

      it "Has badge + of positive branch" do
        expect(positive_sub_branch.badge).to eq "+"
      end

      it "Has badge - of negative branch" do
        expect(negative_sub_branch.badge).to eq "-"
      end

      it "Return both sub branches of root branch" do
        expect(root_branch.sub_branches(branches).count).to eq(2)
        expect(root_branch.sub_branches(branches).map(&:type)).to eq([:then, :else])
      end

      it "Detects the if inline branch given" do
        expect(root_branch.inline_branch?(inline_branches)).to eq(true)
      end

      it "Correct report branch report" do
        expect(positive_sub_branch.report).to eq([0, "+"])
        expect(negative_sub_branch.report).to eq([0, "-"])
      end
    end

    context "A source branch case..when..else" do
      let(:results) do
        [[:case, 0, 1, 4, 10, 4],
         [:when, 1, 2, 6, 8, 4],
         [:when, 2, 3, 8, 10, 4],
         [:else, 0, 1, 4, 10, 4],
         [:else, 3, 4, 10, 12, 4]]
      end

      let(:case_branch) do
        SimpleCov::SourceFile::Branch.new(*(results[0] + [nil]))
      end

      let(:branches_without_else) do
        [case_branch,
         SimpleCov::SourceFile::Branch.new(*(results[1] + [0])),
         SimpleCov::SourceFile::Branch.new(*(results[2] + [0])),
         SimpleCov::SourceFile::Branch.new(*(results[3] + [0]))]
      end

      let(:branches_with_else) do
        [case_branch,
         SimpleCov::SourceFile::Branch.new(*(results[1] + [0])),
         SimpleCov::SourceFile::Branch.new(*(results[2] + [0])),
         SimpleCov::SourceFile::Branch.new(*(results[4] + [0]))]
      end

      it "When branche badge is positive" do
        expect(branches_without_else[1].badge.to_sym).to eq(:+)
      end

      it "Has right `case` sub branches which having else inside" do
        expect(case_branch.sub_branches(branches_with_else).count).to eq(3)
        expect(case_branch.sub_branches(branches_with_else).map(&:type)).to eq([:when, :when, :else])
      end

      it "Has right `case` sub branches which does not have else inside" do
        expect(case_branch.sub_branches(branches_without_else).count).to eq(2)
        expect(case_branch.sub_branches(branches_without_else).map(&:type)).to eq([:when, :when])
      end

      it "Has correct branch report (`when` always positive)" do
        expect(branches_without_else[1].report).to eq([0, "+"])
        expect(branches_without_else[2].report).to eq([0, "+"])
      end
    end

    context "A source branch with coverage" do
      let(:covered_branch) do
        attrs = [:when, 1, 2, 6, 8, 4]
        branch = SimpleCov::SourceFile::Branch.new(*(attrs + [0]))
        branch.coverage = 5
        branch
      end

      it "Is covered" do
        expect(covered_branch).to be_covered
      end

      it "Is not missed" do
        expect(covered_branch).not_to be_missed
      end
    end

    context "A source branch with out coverage" do
      let(:covered_branch) do
        attrs = [:when, 1, 2, 6, 8, 4]
        branch = SimpleCov::SourceFile::Branch.new(*(attrs + [0]))
        branch.coverage = 0
        branch
      end

      it "Is covered" do
        expect(covered_branch).not_to be_covered
      end

      it "Is not missed" do
        expect(covered_branch).to be_missed
      end
    end
  end
end
