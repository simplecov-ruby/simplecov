# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Combine::CoverageAccumulator do
  # A real, executed file: some line ran, and its branch tuples come from
  # Coverage, so they sit at the exact positions Coverage reports.
  let(:executed) do
    {
      "lines" => [nil, 1, 1, 0, nil],
      "branches" => {
        [:if, 0, 2, 2, 4, 10] => {[:then, 1, 3, 4, 3, 10] => 1, [:else, 2, 4, 4, 4, 10] => 0}
      }
    }
  end

  # A simulated (tracked-but-never-loaded) file: every line is nil / 0, and
  # its branch tuples are synthesized. Here the `if` condition's end column
  # has drifted (…4, 12] vs …4, 10]), the exact failure mode of #1233.
  let(:simulated_drifted) do
    {
      "lines" => [nil, 0, 0, 0, nil],
      "branches" => {
        [:if, 0, 2, 2, 4, 12] => {[:then, 1, 3, 4, 3, 10] => 0, [:else, 2, 4, 4, 4, 12] => 0}
      }
    }
  end

  def merge(*coverages)
    accumulator = described_class.new
    coverages.each { |coverage| accumulator.absorb("file.rb" => coverage) }
    accumulator.result.fetch("file.rb")
  end

  # This reads straight off a parsed resultset, which is external input: a file
  # written by another SimpleCov version, or hand-edited, can carry anything
  # under "lines". Reconciliation calls it on raw resultset data, so a bare
  # `any?` would raise NoMethodError out of the middle of a merge.
  describe ".executed?" do
    it "is true when any line ran" do
      expect(described_class.executed?([nil, 0, 2])).to be(true)
    end

    it "is false for a simulated file's all-nil-or-zero lines" do
      expect(described_class.executed?([nil, 0, 0])).to be(false)
    end

    it "is false when there is no lines table at all" do
      expect(described_class.executed?(nil)).to be(false)
    end

    it "coerces a malformed scalar rather than raising" do
      expect(described_class.executed?(3)).to be(true)
      expect(described_class.executed?(0)).to be(false)
    end
  end

  describe "#result" do
    it "is nil when nothing was absorbed, so 'no results' is distinguishable" do
      expect(described_class.new.result).to be_nil
    end

    it "is an empty hash once an empty resultset was absorbed" do
      expect(described_class.new.absorb({}).result).to eq({})
    end

    it "ignores a nil coverage the way a missing merge side is ignored" do
      expect(described_class.new.absorb(nil).result).to be_nil
    end

    it "returns a file only one resultset carried untouched" do
      only = {"lines" => [nil, 1]}
      accumulator = described_class.new.absorb("file.rb" => only)

      expect(accumulator.result.fetch("file.rb")).to be(only)
    end

    it "keeps files in first-seen order across resultsets" do
      accumulator = described_class.new
      accumulator.absorb("b.rb" => {"lines" => [1]}, "a.rb" => {"lines" => [1]})
      accumulator.absorb("a.rb" => {"lines" => [1]}, "c.rb" => {"lines" => [1]})

      expect(accumulator.result.keys).to eq(%w[b.rb a.rb c.rb])
    end
  end

  describe "line merging" do
    it "sums counts and treats a line relevant on either side as relevant" do
      merged = merge({"lines" => [nil, 0, nil, 0]}, {"lines" => [nil, nil, 0, 0]})

      expect(merged["lines"]).to eq([nil, 0, 0, 0])
    end

    it "grows to the longest side" do
      merged = merge({"lines" => [1, 1]}, {"lines" => [1, 1, nil, 2]})

      expect(merged["lines"]).to eq([2, 2, nil, 2])
    end

    it "does not mutate the absorbed resultsets" do
      first = {"lines" => [1, 1]}
      second = {"lines" => [1, 1]}

      merge(first, second)

      expect(first["lines"]).to eq([1, 1])
      expect(second["lines"]).to eq([1, 1])
    end

    it "sums across more than two resultsets" do
      merged = merge({"lines" => [nil, 1]}, {"lines" => [nil, 4]}, {"lines" => [nil, 2]})

      expect(merged["lines"]).to eq([nil, 7])
    end
  end

  # Every resultset SimpleCov itself writes carries a lines table, but the
  # merge has to stay total: a hand-written or third-party resultset need
  # not include one, and a half-merged file must not raise.
  describe "coverage entries without a lines table" do
    it "takes the lines from whichever side has them" do
      expect(merge({}, {"lines" => [nil, 1]})["lines"]).to eq([nil, 1])
      expect(merge({"lines" => [nil, 1]}, {})["lines"]).to eq([nil, 1])
    end

    it "reports no lines when neither side has them" do
      expect(merge({}, {})["lines"]).to be_nil
    end
  end

  describe "branch merging", if: SimpleCov.branch_coverage_supported? do
    around do |example|
      SimpleCov.enable_coverage(:branch)
      example.run
      SimpleCov.clear_coverage_criteria
    end

    it "drops a simulated file's branches when the other side was executed" do
      # Only the executed side's real tuple survives — the drifted one would
      # otherwise be a phantom, permanently-missed branch after merge.
      expect(merge(executed, simulated_drifted)["branches"].keys).to eq([[:if, 0, 2, 2, 4, 10]])
    end

    it "is order-independent (simulated first)" do
      expect(merge(simulated_drifted, executed)["branches"].keys).to eq([[:if, 0, 2, 2, 4, 10]])
    end

    it "still merges the lines from the simulated side" do
      # Line shape is authoritative on both sides, so lines combine as usual
      # (the simulated side contributes its zeros / relevance).
      expect(merge(executed, simulated_drifted)["lines"]).to eq([nil, 1, 1, 0, nil])
    end

    it "drops a simulated file absorbed after an executed one and a peer" do
      # The accumulated side only becomes executed part-way through, which is
      # the case a pairwise fold got right by re-reading it every step.
      merged = merge(simulated_drifted, executed, simulated_drifted)

      expect(merged["branches"].keys).to eq([[:if, 0, 2, 2, 4, 10]])
    end

    it "keeps both branch sets when neither side was executed" do
      # Two simulated copies of a never-loaded file: no real data exists, so
      # its branches still count toward the denominator (#1059). If their
      # tuples happen to disagree, both survive — denominator inflation, the
      # acceptable fallback, rather than a false miss on a covered file.
      other = {
        "lines" => [nil, 0, 0, 0, nil],
        "branches" => {[:if, 0, 2, 2, 4, 20] => {[:then, 1, 3, 4, 3, 10] => 0, [:else, 2, 4, 4, 4, 20] => 0}}
      }

      expect(merge(simulated_drifted, other)["branches"].keys)
        .to contain_exactly([:if, 0, 2, 2, 4, 12], [:if, 0, 2, 2, 4, 20])
    end

    it "unions two executed runs of the same file normally" do
      other_run = {
        "lines" => [nil, 1, 1, 1, nil],
        "branches" => {
          [:if, 0, 2, 2, 4, 10] => {[:then, 1, 3, 4, 3, 10] => 4, [:else, 2, 4, 4, 4, 10] => 5}
        }
      }

      arms = merge(executed, other_run)["branches"][[:if, 0, 2, 2, 4, 10]]

      expect(arms[[:then, 1, 3, 4, 3, 10]]).to eq(5)
      expect(arms[[:else, 2, 4, 4, 4, 10]]).to eq(5)
    end

    # Absent lines do not mean a side never ran: a branch-only or method-only
    # run omits them even for the files it loaded. Judging that side as
    # synthesized discarded the real tuples it carried, which is the opposite
    # of what this change is for.
    context "when one side carries no lines table" do
      let(:line_only) { {"lines" => [nil, 1, 1]} }
      let(:branch_only) do
        {"branches" => {[:if, 0, 2, 2, 4, 10] => {[:then, 1, 3, 4, 3, 10] => 7, [:else, 2, 4, 4, 4, 10] => 3}}}
      end

      it "keeps the tuples it carried rather than judging it simulated" do
        arms = merge(line_only, branch_only)["branches"][[:if, 0, 2, 2, 4, 10]]

        expect(arms.values.sum).to eq(10)
      end

      it "answers the same whichever side is absorbed first" do
        expect(merge(line_only, branch_only)).to eq(merge(branch_only, line_only))
      end
    end

    # Branch coverage is on in this process, so the criterion survives the
    # reconciliation even though the side that ran carried no table for it.
    it "reports an empty table when the executed side measured no branches" do
      expect(merge(simulated_drifted, {"lines" => [nil, 1, 1]})["branches"]).to eq({})
    end

    it "reports an empty table when the sides carried one and it was empty" do
      empty = {"lines" => [nil, 1], "branches" => {}}

      expect(merge(empty, empty)["branches"]).to eq({})
    end
  end

  describe "method merging", if: SimpleCov.method_coverage_supported? do
    around do |example|
      SimpleCov.enable_coverage(:method)
      example.run
      SimpleCov.clear_coverage_criteria
    end

    it "drops a simulated file's methods when the other side was executed" do
      executed_methods = {"lines" => [nil, 1, 1], "methods" => {["Foo", :bar, 2, 2, 3, 5] => 1}}
      # Drifted end column, the method-coverage analogue of #1233.
      simulated_methods = {"lines" => [nil, 0, 0], "methods" => {["Foo", :bar, 2, 2, 3, 7] => 0}}

      expect(merge(executed_methods, simulated_methods)["methods"].keys).to eq([["Foo", :bar, 2, 2, 3, 5]])
    end

    it "takes the executed side's methods when it is absorbed second" do
      # The mirror of the case above: what is accumulated so far is the
      # simulated side, and the executed side has to replace it.
      simulated_methods = {"lines" => [nil, 0, 0], "methods" => {["Foo", :bar, 2, 2, 3, 7] => 0}}
      executed_methods = {"lines" => [nil, 1, 1], "methods" => {["Foo", :bar, 2, 2, 3, 5] => 1}}

      expect(merge(simulated_methods, executed_methods)["methods"].keys).to eq([["Foo", :bar, 2, 2, 3, 5]])
    end

    it "sums hit counts for the same method across resultsets" do
      merged = merge(
        {"lines" => [nil, 1], "methods" => {["Foo", :bar, 2, 2, 3, 5] => 1}},
        {"lines" => [nil, 1], "methods" => {["Foo", :bar, 2, 2, 3, 5] => 4}}
      )

      expect(merged["methods"]).to eq({["Foo", :bar, 2, 2, 3, 5] => 5})
    end

    it "keeps an empty table when only the dropped side carried methods" do
      # The executed side wins and has no methods, but methods were measured,
      # so the criterion stays in play rather than vanishing from the file.
      merged = merge({"lines" => [nil, 1]}, {"lines" => [nil, 0], "methods" => {}})

      expect(merged["methods"]).to eq({})
    end

    it "reports nil when no resultset carried methods at all" do
      expect(merge({"lines" => [nil, 1]}, {"lines" => [nil, 1]})["methods"]).to be_nil
    end
  end

  # A merge runs on behalf of the processes that produced the resultsets and
  # does not necessarily share their configuration: `simplecov merge` never ran
  # SimpleCov.start at all. Dropping a table this process did not ask for loses
  # branch data the producers measured, and loses it asymmetrically, since a
  # file only one resultset carried is passed through untouched.
  describe "when this process does not measure a criterion the data carries" do
    around do |example|
      SimpleCov.clear_coverage_criteria
      example.run
      SimpleCov.clear_coverage_criteria
    end

    it "keeps the branch table the resultsets carried" do
      expect(merge(executed, executed)["branches"]).not_to be_empty
    end

    it "omits the table when neither this process nor the data has one" do
      expect(merge({"lines" => [nil, 1]}, {"lines" => [nil, 1]})).not_to have_key("branches")
    end

    # The side that ran decides which criteria the file carries, not just
    # their tuples. A simulated side's synthesized branches are dropped as
    # usual, and the criterion goes with them: keeping an empty table would
    # claim the file has no branches when the truth is nobody measured them
    # in the run that executed it.
    it "does not keep a criterion only the dropped side carried" do
      executed_line_only = {"lines" => [nil, 1, 1]}

      expect(merge(executed_line_only, simulated_drifted)).not_to have_key("branches")
    end

    it "answers the same whichever side is absorbed first" do
      executed_line_only = {"lines" => [nil, 1, 1]}

      expect(merge(executed_line_only, simulated_drifted))
        .to eq(merge(simulated_drifted, executed_line_only))
    end

    it "gives a merged file the same shape as one a single resultset carried" do
      accumulator = described_class.new
      accumulator.absorb("merged.rb" => executed, "alone.rb" => executed)
      accumulator.absorb("merged.rb" => executed)
      result = accumulator.result

      expect(result.fetch("merged.rb").keys).to eq(result.fetch("alone.rb").keys)
    end
  end
end
