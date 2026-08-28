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

    it "answers false for non-numeric garbage rather than raising" do
      expect(described_class.executed?("oops")).to be(false)
      expect(described_class.executed?({"1" => 2})).to be(false)
      expect(described_class.executed?([nil, "3", true])).to be(false)
    end

    it "counts a JSON float like an integer" do
      expect(described_class.executed?([nil, 1.0])).to be(true)
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

    # A file only one resultset carried comes back exactly as it came in,
    # whatever it was: a resultset written by another tool can carry
    # anything under a filename, and coercing it here would only hide it
    # from the code that does check.
    it "passes an entry that is not a coverage hash through untouched" do
      accumulator = described_class.new.absorb("file.rb" => nil)

      expect(accumulator.result).to eq("file.rb" => nil)
    end

    # Not just the falsey ones: anything that is not an accumulated file is
    # handed back as it arrived, rather than coerced towards a hash.
    it "passes an entry that is neither a coverage hash nor nil through untouched" do
      entry = [1, 2]
      accumulator = described_class.new.absorb("file.rb" => entry)

      expect(accumulator.result.fetch("file.rb")).to be(entry)
    end

    it "keeps files in first-seen order across resultsets" do
      accumulator = described_class.new
      accumulator.absorb("b.rb" => {"lines" => [1]}, "a.rb" => {"lines" => [1]})
      accumulator.absorb("a.rb" => {"lines" => [1]}, "c.rb" => {"lines" => [1]})

      expect(accumulator.result.keys).to eq(%w[b.rb a.rb c.rb])
    end

    # A file more than one resultset carried is held as a `MergedFile` for
    # as long as the fold runs, and becomes the plain hash the rest of
    # SimpleCov reads only here.
    context "when more than one resultset carried a file" do
      around do |example|
        SimpleCov.clear_coverage_criteria
        example.run
        SimpleCov.clear_coverage_criteria
      end

      it "is the merged coverage as a plain hash" do
        accumulator = described_class.new
        accumulator.absorb("file.rb" => {"lines" => [nil, 3]})
        accumulator.absorb("file.rb" => {"lines" => [nil, 4]})

        expect(accumulator.result).to eq("file.rb" => {"lines" => [nil, 7]})
      end

      it "converts every merged file, not just the first" do
        accumulator = described_class.new
        accumulator.absorb("a.rb" => {"lines" => [3]}, "b.rb" => {"lines" => [5]})
        accumulator.absorb("a.rb" => {"lines" => [4]}, "b.rb" => {"lines" => [6]})

        expect(accumulator.result).to eq("a.rb" => {"lines" => [7]}, "b.rb" => {"lines" => [11]})
      end
    end
  end

  # `ResultMerger` folds `[[command_name], coverage]` pairs, reading each
  # resultset off disk only as the fold asks for it.
  describe "folding command names and coverage together" do
    around do |example|
      SimpleCov.clear_coverage_criteria
      example.run
      SimpleCov.clear_coverage_criteria
    end

    it "concatenates the command names and merges the coverage" do
      pairs = [
        [["rspec"], {"file.rb" => {"lines" => [nil, 3]}}],
        [%w[cucumber minitest], {"file.rb" => {"lines" => [nil, 4]}}]
      ]

      expect(described_class.fold(pairs))
        .to eq([%w[rspec cucumber minitest], {"file.rb" => {"lines" => [nil, 7]}}])
    end

    it "reports no coverage at all when there are no pairs" do
      expect(described_class.fold([])).to eq([[], nil])
    end

    it "keeps the command names of a pair that carried no coverage" do
      expect(described_class.fold([[["rspec"], nil]])).to eq([["rspec"], nil])
    end

    # `ResultMerger.absorb_results` hands in a lazy enumerable so a big CI
    # run's resultsets are never all in memory at once. The fold only
    # iterates, so it must not need a materialized collection.
    it "folds a lazy enumerable, reading one pair at a time" do
      read = []
      pairs = [3, 4].lazy.map do |count|
        read << count
        [["run#{count}"], {"file.rb" => {"lines" => [count]}}]
      end

      expect(described_class.fold(pairs)).to eq([%w[run3 run4], {"file.rb" => {"lines" => [7]}}])
      expect(read).to eq([3, 4])
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

    # Branch coverage is on, so a file that simply has no branches still
    # advertises the criterion rather than looking unmeasured.
    it "reports an empty table when no resultset carried branches at all" do
      expect(merge({"lines" => [nil, 1]}, {"lines" => [nil, 1]})["branches"]).to eq({})
    end

    it "keeps the accumulated branches when a later resultset carries none" do
      expect(merge(executed, {"lines" => [nil, 1, 1]})["branches"]).to eq(executed["branches"])
    end

    # An empty lines table is not evidence that a side never ran, any more
    # than an absent one is, so neither side's tuples are synthesized and
    # both survive.
    context "when a side carries an empty lines table" do
      let(:empty_lines) do
        {"lines" => [], "branches" => {[:if, 0, 2, 2, 4, 12] => {[:then, 1, 3, 4, 3, 10] => 0}}}
      end

      it "unions the tuples when it is the accumulated side" do
        expect(merge(empty_lines, executed)["branches"].keys)
          .to contain_exactly([:if, 0, 2, 2, 4, 12], [:if, 0, 2, 2, 4, 10])
      end

      it "unions the tuples when it is the incoming side" do
        expect(merge(executed, empty_lines)["branches"].keys)
          .to contain_exactly([:if, 0, 2, 2, 4, 10], [:if, 0, 2, 2, 4, 12])
      end
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

    # A file the report carries no method table for stays without one,
    # rather than gaining an empty table that reads as "measured, none
    # covered".
    it "leaves a file with no method table without one" do
      expect(merge({"lines" => [nil, 1]}, {"lines" => [nil, 1]})).not_to have_key("methods")
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

    # The nil-until-carried rule must not depend on which reconcile path
    # ran: an executed-vs-simulated pair (either order) with no methods
    # anywhere answers exactly like the all-executed union above. The
    # persisted resultset shape feeds later merges, so nil-vs-empty is
    # not cosmetic there.
    it "reports nil on the drop path when no resultset carried methods" do
      expect(merge({"lines" => [nil, 1]}, {"lines" => [nil, 0]})["methods"]).to be_nil
    end

    it "reports nil on the replace path when no resultset carried methods" do
      expect(merge({"lines" => [nil, 0]}, {"lines" => [nil, 1]})["methods"]).to be_nil
    end

    # An explicit null is not a table. A resultset can carry one (JSON has
    # no other way to write "measured nothing here"), and the dropped side
    # of a reconciliation then has no methods to stand in for, so the
    # criterion stays absent rather than turning into an empty table.
    it "reports nil when the dropped side carried an explicit null for methods" do
      merged = merge({"lines" => [nil, 1]}, {"lines" => [nil, 0], "methods" => nil})

      expect(merged).not_to have_key("methods")
    end

    it "keeps an empty table when only the replaced side carried methods" do
      # The mirror of the dropped-side case above, so the answer does not
      # depend on absorption order.
      merged = merge({"lines" => [nil, 0], "methods" => {}}, {"lines" => [nil, 1]})

      expect(merged["methods"]).to eq({})
    end

    # Both sides ran, so their tuples are unioned: a criterion only the
    # incoming side carries comes into play, and one only the accumulated
    # side carries survives.
    it "picks up a method table only a later resultset carries" do
      merged = merge({"lines" => [nil, 1]}, {"lines" => [nil, 1], "methods" => {["Foo", :bar, 2, 2, 3, 5] => 3}})

      expect(merged["methods"]).to eq(["Foo", :bar, 2, 2, 3, 5] => 3)
    end

    it "keeps the accumulated methods when a later resultset carries none" do
      merged = merge({"lines" => [nil, 1], "methods" => {["Foo", :bar, 2, 2, 3, 5] => 3}}, {"lines" => [nil, 1]})

      expect(merged["methods"]).to eq(["Foo", :bar, 2, 2, 3, 5] => 3)
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

    # Both sides carry the same condition, so its arms sum. Dropping the
    # table on the way in because this process did not ask for branches
    # would lose the first side's counts, not just the criterion.
    it "keeps the branch table the resultsets carried" do
      expect(merge(executed, executed)["branches"]).to eq(
        [:if, 0, 2, 2, 4, 10] => {[:then, 1, 3, 4, 3, 10] => 2, [:else, 2, 4, 4, 4, 10] => 0}
      )
    end

    it "keeps the method table the resultsets carried" do
      with_methods = {"lines" => [nil, 1], "methods" => {["Foo", :bar, 2, 2, 3, 5] => 3}}

      expect(merge(with_methods, with_methods)["methods"]).to eq(["Foo", :bar, 2, 2, 3, 5] => 6)
    end

    # The accumulated side has no table of its own to fold into: this
    # process measures neither criterion, and the first resultset carried
    # neither. The tuples the second one carries still have to survive.
    it "picks up a branch table only a later resultset carries" do
      expect(merge({"lines" => [nil, 1, 1]}, executed)["branches"]).to eq(executed["branches"])
    end

    it "picks up a method table the data carries and this process does not" do
      merged = merge({"lines" => [nil, 1]}, {"lines" => [nil, 1], "methods" => {["Foo", :bar, 2, 2, 3, 5] => 3}})

      expect(merged["methods"]).to eq(["Foo", :bar, 2, 2, 3, 5] => 3)
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

    # The same rule for methods, on both reconciliation paths: an empty
    # table stands in for a blanked side only for a process that measures
    # methods itself. This one does not, so the criterion goes with the
    # tuples that were dropped.
    context "when only the side whose tuples are dropped carried methods" do
      let(:simulated_methods) { {"lines" => [nil, 0], "methods" => {["Foo", :bar, 2, 2, 3, 5] => 0}} }
      let(:executed_line_only) { {"lines" => [nil, 1]} }

      it "does not keep the table when the accumulated side is replaced" do
        expect(merge(simulated_methods, executed_line_only)).not_to have_key("methods")
      end

      it "does not keep the table when the incoming side is dropped" do
        expect(merge(executed_line_only, simulated_methods)).not_to have_key("methods")
      end
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
