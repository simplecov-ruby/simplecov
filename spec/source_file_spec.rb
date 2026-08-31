# frozen_string_literal: true

require "helper"
require "support/coverage_fixtures"

COVERAGE_FOR_SAMPLE_RB = {
  "lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, 1, 0, nil, nil, nil],
  "branches" => {}
}.freeze

COVERAGE_FOR_SAMPLE_RB_WITH_MORE_LINES = {
  "lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, nil, nil, nil, nil, nil, nil]
}.freeze

COVERAGE_WITH_NIL_BRANCHES = {
  "lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, 1, 0, nil, nil, nil],
  "branches" => nil
}.freeze

COVERAGE_FOR_SKIPPED_RB = {"lines" => [nil, nil, nil, nil]}.freeze

COVERAGE_FOR_SKIPPED_RB_2 = {"lines" => [nil, nil, 0, nil]}.freeze

COVERAGE_FOR_SKIPPED_AND_EXECUTED_RB = {
  "lines" => [nil, nil, 1, 1, 0, 0, nil, 0, nil, nil, nil, nil],
  "branches" => {
    [:if, 0, 5, 4, 9, 7] =>
      {[:then, 1, 6, 6, 6, 7] => 1, [:else, 2, 8, 6, 8, 7] => 0}
  }
}.freeze

COVERAGE_FOR_SINGLE_LINE = {"lines" => [nil]}.freeze

COVERAGE_FOR_DOUBLE_LINES = {"lines" => [nil, 1]}.freeze

COVERAGE_FOR_TRIPLE_LINES = {"lines" => [nil, nil, 1]}.freeze

DEGREE_135_LINE = "puts \"135°C\"\n"

COVERAGE_FOR_METHODS_RB = {
  "lines" => [1, 1, 1, 1, nil, nil, 1, nil, 1, 1, nil, nil, 1, 0, nil, nil, nil, 1],
  "branches" => {},
  "methods" => {
    ["A", :method1, 2, 2, 5, 5] => 1,
    ["A", :method2, 9, 2, 11, 5] => 1,
    ["A", :method3, 13, 2, 15, 5] => 0
  }
}.freeze

RSpec.describe SimpleCov::SourceFile do
  def source_file_with(coverage_data, source_lines)
    SimpleCov::SourceFile.new("inline_source.rb", coverage_data).tap do |file|
      file.instance_variable_set(:@src, source_lines)
    end
  end

  context "when a source file initialized with some coverage data" do
    subject(:source_file) do
      described_class.new(source_fixture("sample.rb"), COVERAGE_FOR_SAMPLE_RB)
    end

    it "has a filename" do
      expect(source_file.filename).not_to be_nil
    end

    it "has source equal to src" do
      expect(source_file.src).to eq(source_file.source)
    end

    it "has a project filename which removes the project directory" do
      expect(source_file.project_filename).to eq("spec/fixtures/sample.rb")
    end

    it "has source_lines equal to lines" do
      expect(source_file.lines).to eq(source_file.source_lines)
    end

    it "has 16 source lines" do
      expect(source_file.lines.count).to eq(16)
    end

    it "has all source lines of type SimpleCov::SourceFile::Line" do
      expect(source_file.lines).to all(be_a SimpleCov::SourceFile::Line)
    end

    it "has 'class Foo' as line(2).source" do
      expect(source_file.line(2).source).to eq("class Foo\n")
    end

    describe "line coverage" do
      it "returns lines number 2, 3, 4, 7 for covered_lines" do
        expect(source_file.covered_lines.map(&:line)).to eq([2, 3, 4, 7])
      end

      it "returns lines number 8 for missed_lines" do
        expect(source_file.missed_lines.map(&:line)).to eq([8])
      end

      it "returns lines number 1, 5, 6, 9, 10, 16 for never_lines" do
        expect(source_file.never_lines.map(&:line)).to eq([1, 5, 6, 9, 10, 16])
      end

      it "returns line numbers 11, 12, 13, 14, 15 for skipped_lines" do
        expect(source_file.skipped_lines.map(&:line)).to eq([11, 12, 13, 14, 15])
      end

      it "has 80% covered_percent" do
        expect(source_file.covered_percent).to eq(80.0)
      end
    end

    describe "branch coverage" do
      it "has total branches count 0" do
        expect(source_file.total_branches.size).to eq(0)
      end

      it "has covered branches count 0" do
        expect(source_file.covered_branches.size).to eq(0)
      end

      it "has missed branches count 0" do
        expect(source_file.missed_branches.size).to eq(0)
      end

      it "is considered 100% branches covered" do
        expect(source_file.covered_percent(:branch)).to eq(100.0)
      end

      it "has branch coverage report" do
        expect(source_file.branches_report).to eq({})
      end
    end

    describe "method coverage" do
      it "has no methods" do
        expect(source_file.covered_methods.size).to eq(0)
        expect(source_file.missed_methods.size).to eq(0)
      end

      it "is considered 100% methods covered" do
        expect(source_file.covered_percent(:method)).to eq(100.0)
      end
    end
  end

  context "when file with methods" do
    subject(:source_file) do
      described_class.new(source_fixture("methods.rb"), coverage_for_methods_rb)
    end

    let(:coverage_for_methods_rb) { COVERAGE_FOR_METHODS_RB }

    describe "method coverage" do
      it "has 3 total methods" do
        expect(source_file.methods.size).to eq(3)
      end

      it "has 2 covered methods" do
        expect(source_file.covered_methods.size).to eq(2)
      end

      it "has 1 missed method" do
        expect(source_file.missed_methods.size).to eq(1)
      end

      it "is considered 66.(6)% methods covered" do
        expect(source_file.covered_percent(:method)).to eq(66.66666666666667)
      end
    end

    describe "line coverage" do
      it "has line coverage" do
        expect(source_file.covered_percent).to eq 90.0
      end

      it "has 9 covered lines" do
        expect(source_file.covered_lines.size).to eq 9
      end

      it "has 1 missed line" do
        expect(source_file.missed_lines.size).to eq 1
      end

      it "has 10 relevant lines" do
        expect(source_file.relevant_lines).to eq 10
      end
    end
  end

  context "when file with methods from JSON round-trip" do
    subject(:source_file) do
      described_class.new(source_fixture("methods.rb"), coverage_data)
    end

    let(:coverage_data) do
      {
        "lines" => [1, 1, 1, 1, nil, nil, 1, nil, 1, 1, nil, nil, 1, 0, nil, nil, nil, 1],
        "branches" => {},
        "methods" => {
          '["A", :method1, 2, 2, 5, 5]' => 1,
          '["A", :method2, 9, 2, 11, 5]' => 1,
          '["A", :method3, 13, 2, 15, 5]' => 0
        }
      }
    end

    it "correctly parses stringified method keys" do
      expect(source_file.methods.size).to eq(3)
      expect(source_file.covered_methods.size).to eq(2)
      expect(source_file.missed_methods.size).to eq(1)
    end

    it "restores method info correctly" do
      method = source_file.methods.first
      expect(method.class_name).to eq("A")
      expect(method.method_name).to eq(:method1)
      expect(method.start_line).to eq(2)
    end
  end

  context "when method keys with bare class names from JSON round-trip" do
    subject(:source_file) do
      described_class.new(source_fixture("methods.rb"), coverage_data)
    end

    let(:coverage_data) do
      {
        "lines" => [1, 1, 1, 1, nil, nil, 1, nil, 1, 1, nil, nil, 1, 0, nil, nil, nil, 1],
        "branches" => {},
        "methods" => methods_data
      }
    end

    context "with a simple bare class name" do
      let(:methods_data) { {"[A, :method1, 2, 2, 5, 5]" => 1} }

      it "parses the bare class name" do
        method = source_file.methods.first
        expect(method.class_name).to eq("A")
        expect(method.method_name).to eq(:method1)
        expect(method.start_line).to eq(2)
      end
    end

    context "with a namespaced class name" do
      let(:methods_data) { {"[Foo::Bar::Baz, :process, 2, 2, 5, 5]" => 1} }

      it "parses the full namespace as the class name" do
        method = source_file.methods.first
        expect(method.class_name).to eq("Foo::Bar::Baz")
        expect(method.method_name).to eq(:process)
        expect(method.start_line).to eq(2)
      end
    end

    context "with a setter method name" do
      let(:methods_data) { {"[A, :name=, 2, 2, 5, 5]" => 1} }

      it "parses the setter method name including the =" do
        method = source_file.methods.first
        expect(method.class_name).to eq("A")
        expect(method.method_name).to eq(:name=)
        expect(method.start_line).to eq(2)
      end
    end

    context "with a singleton class" do
      let(:methods_data) { {"[#<Class:Foo>, :bar, 2, 2, 5, 5]" => 1} }

      it "parses the singleton class name" do
        method = source_file.methods.first
        expect(method.class_name).to eq("#<Class:Foo>")
        expect(method.method_name).to eq(:bar)
        expect(method.start_line).to eq(2)
      end
    end

    context "with a singleton class of an instance" do
      let(:methods_data) { {"[#<Class:#<Object:0x0>>, :bar, 2, 2, 5, 5]" => 1} }

      it "parses the nested singleton class name" do
        method = source_file.methods.first
        expect(method.class_name).to eq("#<Class:#<Object:0x0>>")
        expect(method.method_name).to eq(:bar)
        expect(method.start_line).to eq(2)
      end
    end
  end

  context "when branches coverage data is explicitly nil" do
    subject(:source_file) do
      described_class.new(source_fixture("sample.rb"), COVERAGE_WITH_NIL_BRANCHES)
    end

    it "returns empty branches without raising NoMethodError" do
      expect(source_file.branches).to eq []
    end

    it "has 0 total branches" do
      expect(source_file.total_branches.size).to eq 0
    end

    it "has 0 covered branches" do
      expect(source_file.covered_branches.size).to eq 0
    end

    it "has 0 missed branches" do
      expect(source_file.missed_branches.size).to eq 0
    end

    it "reports 100% branch coverage (no branches to miss)" do
      expect(source_file.covered_percent(:branch)).to eq 100.0
    end
  end

  context "when file with branches" do
    subject(:source_file) do
      described_class.new(source_fixture("branches.rb"), CoverageFixtures::BRANCHES_RB)
    end

    describe "branch coverage" do
      it "has 50% branch coverage" do
        expect(source_file.covered_percent(:branch)).to eq 50.0
      end

      it "has total branches count 6" do
        expect(source_file.total_branches.size).to eq(6)
      end

      it "has covered branches count 3" do
        expect(source_file.covered_branches.size).to eq(3)
      end

      it "has missed branches count 3" do
        expect(source_file.missed_branches.size).to eq(3)
      end

      it "has coverage report" do
        expect(source_file.branches_report).to eq(
          3 => [[:then, 0], [:else, 1]],
          5 => [[:then, 1], [:else, 0]],
          7 => [[:then, 0]],
          9 => [[:else, 1]]
        )
      end

      it "has line 7 with missed branches branch" do
        expect(source_file.line_with_missed_branch?(7)).to be(true)
      end

      it "has line 3 with missed branches branch" do
        expect(source_file.line_with_missed_branch?(3)).to be(true)
      end

      it "has no missed branch on line 9, whose only branch was taken" do
        expect(source_file.line_with_missed_branch?(9)).to be(false)
      end

      it "has no missed branch on a line that carries no branch at all" do
        expect(source_file.line_with_missed_branch?(1)).to be(false)
      end

      it "does have branches" do
        expect(source_file.no_branches?).to be(false)
      end
    end

    describe "line coverage" do
      it "has line coverage" do
        expect(source_file.covered_percent).to be_within(0.01).of(85.71)
      end

      it "has 6 covered lines" do
        expect(source_file.covered_lines.size).to eq 6
      end

      it "has 1 missed line" do
        expect(source_file.missed_lines.size).to eq 1
      end

      it "has 7 relevant lines" do
        expect(source_file.relevant_lines).to eq 7
      end
    end
  end

  context "when coverage data contains more entries than the source has lines" do
    subject(:source_file) do
      described_class.new(source_fixture("sample.rb"), COVERAGE_FOR_SAMPLE_RB_WITH_MORE_LINES)
    end

    it "has 16 source lines regardless of extra data in coverage array" do
      expect(source_file.lines.count).to eq(16)
    end

    it "does not output to stderr" do
      expect { source_file.lines }.not_to output.to_stderr
    end
  end

  context "when A file that has inline branches" do
    subject(:source_file) do
      described_class.new(source_fixture("inline.rb"), CoverageFixtures::INLINE_RB)
    end

    it "has branches report on 3 lines" do
      expect(source_file.branches_report.keys.size).to eq(3)
      expect(source_file.branches_report.keys).to eq([3, 6, 8])
    end

    it "has covered branches count 2" do
      expect(source_file.covered_branches.size).to eq(2)
    end

    it "has dual element in condition at line 3 report" do
      expect(source_file.branches_report[3]).to eq([[:then, 1], [:else, 0]])
    end

    it "has branches coverage percent 50.00" do
      expect(source_file.covered_percent(:branch)).to eq(50.00)
    end
  end

  context "when a file that is never relevant" do
    subject(:source_file) do
      described_class.new(source_fixture("never.rb"), CoverageFixtures::NEVER_RB)
    end

    it "has 0.0 covered_strength" do
      expect(source_file.covered_strength).to eq 0.0
    end

    it "has 100.0 covered_percent" do
      expect(source_file.covered_percent).to eq 100.0
    end

    it "has 100.0 branch coverage" do
      expect(source_file.covered_percent(:branch)).to eq(100.00)
    end
  end

  context "when a file where nothing is ever executed mixed with skipping #563" do
    subject(:source_file) do
      described_class.new(source_fixture("skipped.rb"), COVERAGE_FOR_SKIPPED_RB)
    end

    it "has 0.0 covered_strength" do
      expect(source_file.covered_strength).to eq 0.0
    end

    it "has 0.0 covered_percent" do
      expect(source_file.covered_percent).to eq 100.0
    end
  end

  context "when a file where everything is skipped and missed #563" do
    subject(:source_file) do
      described_class.new(source_fixture("skipped.rb"), COVERAGE_FOR_SKIPPED_RB_2)
    end

    it "has 0.0 covered_strength" do
      expect(source_file.covered_strength).to eq 0.0
    end

    it "has 0.0 covered_percent" do
      expect(source_file.covered_percent).to eq 100.0
    end

    it "has no covered or missed lines" do
      expect(source_file.covered_lines).to be_empty
      expect(source_file.missed_lines).to be_empty
    end
  end

  context "when a file where everything is skipped/irrelevant but executed #563" do
    subject(:source_file) do
      described_class.new(source_fixture("skipped_and_executed.rb"), COVERAGE_FOR_SKIPPED_AND_EXECUTED_RB)
    end

    describe "line coverage" do
      it "has no relevant lines" do
        expect(source_file.relevant_lines).to eq(0)
      end

      it "has no covered lines" do
        expect(source_file.covered_lines.size).to eq(0)
      end

      it "has no missed lines" do
        expect(source_file.missed_lines.size).to eq(0)
      end

      it "has a whole lot of skipped lines" do
        expect(source_file.skipped_lines.size).to eq(11)
      end

      it "has 0.0 covered_strength" do
        expect(source_file.covered_strength).to eq 0.0
      end

      it "has 0.0 covered_percent" do
        expect(source_file.covered_percent).to eq 100.0
      end
    end

    describe "branch coverage" do
      it "has an empty branch report" do
        expect(source_file.branches_report).to eq({})
      end

      it "has no branches" do
        expect(source_file.total_branches.size).to eq 0
        expect(source_file.no_branches?).to be true
      end

      it "does has neither covered nor missed branches" do
        expect(source_file.missed_branches.size).to eq 0
        expect(source_file.covered_branches.size).to eq 0
      end
    end
  end

  context "when a file with more complex skipping" do
    subject(:source_file) do
      described_class.new(source_fixture("nocov_complex.rb"), CoverageFixtures::NOCOV_COMPLEX_RB)
    end

    describe "line coverage" do
      it "has 6 relevant lines" do
        expect(source_file.relevant_lines).to eq(5)
      end

      it "has 6 covered lines" do
        expect(source_file.covered_lines.size).to eq(5)
      end

      it "has no missed lines" do
        expect(source_file.missed_lines.size).to eq(0)
      end

      it "has a whole lot of skipped lines" do
        expect(source_file.skipped_lines.size).to eq(11)
      end

      it "has 100.0 covered_percent" do
        expect(source_file.covered_percent).to eq 100.0
      end
    end

    describe "branch coverage" do
      it "has an empty branch report" do
        expect(source_file.branches_report).to eq(
          9 => [[:else, 1]],
          13 => [[:then, 1], [:else, 0]],
          22 => [[:when, 1]]
        )
      end

      it "covers 3/4 branches" do
        expect(source_file.total_branches.size).to eq 4
        expect(source_file.missed_branches.size).to eq 1
        expect(source_file.covered_branches.size).to eq 3
        expect(source_file.covered_strength(:branch)).to eq 0.75
      end
    end
  end

  context "when a file with nested branches" do
    subject(:source_file) do
      described_class.new(source_fixture("nested_branches.rb"), CoverageFixtures::NESTED_BRANCHES_RB)
    end

    describe "line coverage" do
      it "covers 6/7" do
        expect(source_file.covered_percent).to be_within(0.01).of(85.71)
      end
    end

    describe "branch coverage" do
      it "covers 3/5" do
        expect(source_file.total_branches.size).to eq 5
        expect(source_file.covered_branches.size).to eq 3
        expect(source_file.missed_branches.size).to eq 2
      end

      it "registered 2 hits for the while branch" do
        expect(source_file.branches_report[7]).to eq [[:body, 2]]
      end
    end
  end

  context "when a file with case" do
    subject(:source_file) do
      described_class.new(source_fixture("case.rb"), CoverageFixtures::CASE_RB)
    end

    describe "line coverage" do
      it "covers 4/7" do
        expect(source_file.relevant_lines).to eq 7
        expect(source_file.covered_lines.size).to eq 4
        expect(source_file.missed_lines.size).to eq 3
      end
    end

    describe "branch coverage" do
      it "covers 1/4" do
        expect(source_file.total_branches.size).to eq 4
        expect(source_file.covered_branches.size).to eq 1
        expect(source_file.missed_branches.size).to eq 3
      end

      it "covers all the things right" do
        expect(source_file.branches_report).to eq(
          4 => [[:when, 0]],
          6 => [[:when, 1]],
          8 => [[:when, 0]],
          10 => [[:else, 0]]
        )
      end
    end
  end

  context "when a file with case without else" do
    subject(:source_file) do
      described_class.new(source_fixture("case_without_else.rb"), CoverageFixtures::CASE_WITHOUT_ELSE_RB)
    end

    describe "line coverage" do
      it "covers 4/6" do
        expect(source_file.relevant_lines).to eq 6
        expect(source_file.covered_lines.size).to eq 4
        expect(source_file.missed_lines.size).to eq 2
      end
    end

    describe "branch coverage" do
      it "covers 1/4 (counting the else branch)" do
        expect(source_file.total_branches.size).to eq 4
        expect(source_file.covered_branches.size).to eq 1
        expect(source_file.missed_branches.size).to eq 3
      end

      it "marks the non declared else branch as missing at the point of the case" do
        expect(source_file.branches_for_line(3)).to eq [[:else, 0]]
      end

      it "covers the branch that includes 42" do
        expect(source_file.branches_report).to eq(
          3 => [[:else, 0]],
          4 => [[:when, 0]],
          6 => [[:when, 1]],
          8 => [[:when, 0]]
        )
      end
    end
  end

  context "with ignore_branches :implicit_else configured" do
    around do |example|
      previous = SimpleCov.instance_variable_get(:@ignored_branches)&.dup
      capture_stderr { SimpleCov.ignore_branches :implicit_else }
      example.run
    ensure
      SimpleCov.instance_variable_set(:@ignored_branches, previous)
    end

    describe "a file with `case` and no `else` arm" do
      subject(:source_file) do
        described_class.new(source_fixture("case_without_else.rb"), CoverageFixtures::CASE_WITHOUT_ELSE_RB)
      end

      it "drops the synthetic else branch from the totals" do
        expect(source_file.total_branches.size).to eq 3
        expect(source_file.covered_branches.size).to eq 1
        expect(source_file.missed_branches.size).to eq 2
      end

      it "leaves no `:else` entry on the condition line" do
        expect(source_file.branches_for_line(3)).to eq []
      end

      it "still reports the three explicit `when` arms" do
        expect(source_file.branches_report).to eq(
          4 => [[:when, 0]],
          6 => [[:when, 1]],
          8 => [[:when, 0]]
        )
      end
    end

    describe "a file with an explicit `else` arm" do
      subject(:source_file) do
        described_class.new(source_fixture("case.rb"), CoverageFixtures::CASE_RB)
      end

      it "keeps the explicit else branch — the heuristic matches only synthetic ones" do
        expect(source_file.total_branches.size).to eq 4
        expect(source_file.branches_report).to eq(
          4 => [[:when, 0]],
          6 => [[:when, 1]],
          8 => [[:when, 0]],
          10 => [[:else, 0]]
        )
      end
    end

    describe "a file with an inline (ternary) explicit `else`" do
      subject(:source_file) do
        described_class.new(source_fixture("inline.rb"), CoverageFixtures::INLINE_RB)
      end

      it "preserves the ternary's explicit else on the condition's line" do
        expect(source_file.total_branches.size).to eq 4

        line_3_types = source_file.branches_for_line(3).map(&:first).sort
        expect(line_3_types).to eq %i[else then]
      end
    end

    describe "a file with `if`/`unless` constructs (postfix and block)" do
      subject(:source_file) do
        described_class.new(source_fixture("branches.rb"), CoverageFixtures::BRANCHES_RB)
      end

      it "drops the postfix `if`'s synthetic else but keeps the block `if`'s explicit else" do
        else_lines = source_file.branches.select { |b| b.type == :else }.map(&:start_line)
        expect(else_lines).to contain_exactly(5, 10)
      end
    end

    describe "a non-else arm carrying its condition's whole range" do
      subject(:source_file) do
        source_file_with(
          {
            "lines" => [1],
            "branches" => {
              [:if, 0, 1, 0, 1, 10] => {
                [:then, 1, 1, 0, 1, 10] => 1,
                [:else, 2, 1, 0, 1, 10] => 0
              }
            },
            "methods" => {}
          },
          ["x = 1 if y\n"]
        )
      end

      it "drops the else arm and keeps the other one" do
        expect(source_file.branches.map(&:type)).to eq [:then]
      end
    end
  end

  context "with ignore_branches :eval_generated configured", if: SimpleCov::StaticCoverageExtractor.available? do
    subject(:source_file) do
      described_class.new(source_fixture("eval_generated.rb"), CoverageFixtures::EVAL_GENERATED_RB)
    end

    around do |example|
      previous = SimpleCov.instance_variable_get(:@ignored_branches)&.dup
      capture_stderr { SimpleCov.ignore_branches :eval_generated }
      example.run
    ensure
      SimpleCov.instance_variable_set(:@ignored_branches, previous)
    end

    it "drops the eval-generated branch and keeps the real one" do
      condition_lines = source_file.branches.map(&:start_line).uniq.sort
      expect(condition_lines).to eq [4]
    end

    it "leaves the totals consistent with only real branches" do
      expect(source_file.total_branches.size).to eq 2
    end

    describe "with the branch keys stringified by a JSON round-trip" do
      subject(:source_file) do
        described_class.new(source_fixture("eval_generated.rb"), stringified_coverage)
      end

      let(:stringified_coverage) do
        branches = CoverageFixtures::EVAL_GENERATED_RB.fetch("branches").to_h do |condition, arms|
          [condition.to_s, arms.transform_keys(&:to_s)]
        end

        CoverageFixtures::EVAL_GENERATED_RB.merge("branches" => branches)
      end

      it "still drops the eval-generated branch and keeps the real one" do
        expect(source_file.branches.map(&:start_line).uniq).to eq [4]
      end
    end
  end

  context "with ignore_methods :eval_generated configured", if: SimpleCov::StaticCoverageExtractor.available? do
    subject(:source_file) do
      described_class.new(source_fixture("eval_generated.rb"), CoverageFixtures::EVAL_GENERATED_RB)
    end

    around do |example|
      previous = SimpleCov.instance_variable_get(:@ignored_methods)&.dup
      capture_stderr { SimpleCov.ignore_methods :eval_generated }
      example.run
    ensure
      SimpleCov.instance_variable_set(:@ignored_methods, previous)
    end

    it "drops the eval-generated method and keeps the real `def`" do
      method_names = source_file.methods.map(&:method_name)
      expect(method_names).to contain_exactly(:initialize)
    end
  end

  context "without the eval_generated filter (default)", if: SimpleCov::StaticCoverageExtractor.available? do
    subject(:source_file) do
      described_class.new(source_fixture("eval_generated.rb"), CoverageFixtures::EVAL_GENERATED_RB)
    end

    it "keeps every Coverage-reported branch (filter is opt-in)" do
      expect(source_file.total_branches.size).to eq 4
    end

    it "keeps every Coverage-reported method (filter is opt-in)" do
      expect(source_file.methods.map(&:method_name)).to contain_exactly(:hello, :initialize)
    end
  end

  context "when a file with if/elsif" do
    subject(:source_file) do
      described_class.new(source_fixture("elsif.rb"), CoverageFixtures::ELSIF_RB)
    end

    describe "line coverage" do
      it "covers 6/9" do
        expect(source_file.relevant_lines).to eq 9
        expect(source_file.covered_lines.size).to eq 6
        expect(source_file.missed_lines.size).to eq 3
      end
    end

    describe "branch coverage" do
      it "covers 3/6" do
        expect(source_file.total_branches.size).to eq 6
        expect(source_file.covered_branches.size).to eq 3
        expect(source_file.missed_branches.size).to eq 3
      end

      it "covers the branch that includes 42" do
        expect(source_file.branches_report[7]).to eq [[:then, 1]]
      end
    end
  end

  context "when the branch tester script" do
    subject(:source_file) do
      described_class.new(source_fixture("branch_tester_script.rb"), CoverageFixtures::BRANCH_TESTER_RB)
    end

    describe "line coverage" do
      it "covers 18/28" do
        expect(source_file.relevant_lines).to eq 28
        expect(source_file.covered_lines.size).to eq 18
      end
    end

    describe "branch coverage" do
      it "covers 10/24" do
        expect(source_file.total_branches.size).to eq 24
        expect(source_file.covered_branches.size).to eq 11
      end

      it "notifies us of the missing else branch on line 27 that's hit" do
        expect(source_file.branches_report[27]).to eq [[:then, 0], [:else, 1]]
      end
    end
  end

  context "when a file using the deprecated # :nocov: directive" do
    subject(:source_file) do
      described_class.new(source_fixture("single_nocov.rb"), CoverageFixtures::SINGLE_NOCOV_RB)
    end

    before { SimpleCov::SourceFile::SkipChunks.nocov_warned.clear }

    it "warns once per file with the recommended replacement" do
      stderr = capture_stderr { source_file.lines }

      expect(stderr).to include("[DEPRECATION]")
      expect(stderr).to include("# :nocov:")
      expect(stderr).to include("# simplecov:disable")
      expect(stderr).to include("# simplecov:enable")
      expect(stderr).to include(source_fixture("single_nocov.rb"))
    end

    it "deduplicates the warning for the same file across SourceFile instances" do
      capture_stderr { source_file.lines }
      another = described_class.new(source_fixture("single_nocov.rb"), CoverageFixtures::SINGLE_NOCOV_RB)
      stderr = capture_stderr { another.lines }

      expect(stderr).to be_empty
    end
  end

  context "when a file entirely ignored with a single # :nocov:" do
    subject(:source_file) do
      described_class.new(source_fixture("single_nocov.rb"), CoverageFixtures::SINGLE_NOCOV_RB)
    end

    describe "line coverage" do
      it "has all lines skipped" do
        expect(source_file.skipped_lines.size).to eq(source_file.lines.size)
        expect(source_file.skipped_lines.size).to eq(14)
      end

      it "reports 100% coverage on 0/0" do
        expect(source_file.covered_percent).to eq 100.0
        expect(source_file.relevant_lines).to eq 0
        expect(source_file.covered_lines.size).to eq 0
      end
    end

    describe "branch coverage" do
      it "has 100% branch coverage on 0/0" do
        branch_coverage = source_file.coverage_statistics.fetch(:branch)

        expect(branch_coverage.percent).to eq 100.0
        expect(branch_coverage.total).to eq 0
        expect(branch_coverage.covered).to eq 0
      end

      it "has all branches marked as skipped" do
        expect(source_file.branches.all?(&:skipped?)).to be true
      end
    end
  end

  context "when a file with an uneven usage of # :nocov:s" do
    subject(:source_file) do
      described_class.new(source_fixture("uneven_nocovs.rb"), CoverageFixtures::UNEVEN_NOCOVS_RB)
    end

    describe "line coverage" do
      it "has 12 lines skipped" do
        expect(source_file.skipped_lines.size).to eq(12)
      end

      it "reports 100% coverage on 4/4" do
        expect(source_file.covered_percent).to eq 100.0
        expect(source_file.relevant_lines).to eq 4
        expect(source_file.covered_lines.size).to eq 4
      end
    end

    describe "branch coverage" do
      it "has 100% branch coverage on 1/1" do
        branch_coverage = source_file.coverage_statistics.fetch(:branch)

        expect(branch_coverage.percent).to eq 100.0
        expect(branch_coverage.total).to eq 1
        expect(branch_coverage.covered).to eq 1
      end

      it "has 5 branches marked as skipped" do
        expect(source_file.branches.count(&:skipped?)).to eq 5
      end
    end
  end

  context "when a file contains non-ASCII characters" do
    shared_examples_for "converting to UTF-8" do
      it "has all source lines of encoding UTF-8" do
        source_file.lines.each do |line|
          expect(line.source.encoding).to eq(Encoding::UTF_8)
          expect(line.source).to be_valid_encoding
        end
      end
    end

    describe "UTF-8 without magic comment" do
      subject(:source_file) do
        described_class.new(source_fixture("utf-8.rb"), COVERAGE_FOR_SINGLE_LINE)
      end

      it_behaves_like "converting to UTF-8"

      it "has the line with 135°C" do
        expect(source_file.line(1).source).to eq DEGREE_135_LINE
      end
    end

    describe "UTF-8 with magic comment" do
      subject(:source_file) do
        described_class.new(source_fixture("utf-8-magic.rb"), COVERAGE_FOR_DOUBLE_LINES)
      end

      it_behaves_like "converting to UTF-8"

      it "has the line with 135°C" do
        expect(source_file.line(2).source).to eq DEGREE_135_LINE
      end
    end

    describe "EUC-JP with magic comment" do
      subject(:source_file) do
        described_class.new(source_fixture("euc-jp.rb"), COVERAGE_FOR_DOUBLE_LINES)
      end

      it_behaves_like "converting to UTF-8"

      it "has the line with 135°C" do
        expect(source_file.line(2).source).to eq DEGREE_135_LINE
      end
    end

    describe "EUC-JP with magic comment and shebang" do
      subject(:source_file) do
        described_class.new(source_fixture("euc-jp-shebang.rb"), COVERAGE_FOR_TRIPLE_LINES)
      end

      it_behaves_like "converting to UTF-8"

      it "has all the right lines" do
        expect(source_file.lines.map(&:source)).to eq [
          "#!/usr/bin/env ruby\n",
          "# encoding: EUC-JP\n",
          DEGREE_135_LINE
        ]
      end
    end

    describe "invalid UTF-8 bytes without a magic comment" do
      subject(:source_file) do
        described_class.new(invalid_path, COVERAGE_FOR_TRIPLE_LINES)
      end

      let(:tmpdir) { Dir.mktmpdir("simplecov-invalid-utf8-spec-") }
      let(:invalid_path) do
        File.join(tmpdir, "invalid.rb").tap do |path|
          File.binwrite(path, "#!/usr/bin/env ruby\nx = 1 # caf\xE9\ny = 2\n")
        end
      end

      after { FileUtils.remove_entry(tmpdir) }

      it_behaves_like "converting to UTF-8"

      it "replaces the invalid bytes and keeps the rest of the line" do
        expect(source_file.lines.map(&:source)).to eq [
          "#!/usr/bin/env ruby\n",
          "x = 1 # caf�\n",
          "y = 2\n"
        ]
      end

      it "still classifies and reports coverage" do
        expect(source_file.covered_lines.size).to eq 1
      end
    end

    describe "empty euc-jp file" do
      subject(:source_file) do
        described_class.new(source_fixture("empty_euc-jp.rb"), {"lines" => []})
      end

      it "has empty lines" do
        expect(source_file.lines).to be_empty
      end
    end

    context "when a not loaded file (tracked but not required)" do
      subject(:source_file) do
        described_class.new(
          source_fixture("sample.rb"),
          {"lines" => [nil, 1, nil, 1, nil, nil, nil], "branches" => {}, "methods" => {}},
          loaded: false
        )
      end

      it "is marked as not loaded" do
        expect(source_file.not_loaded?).to be true
      end

      it "reports 0% branch coverage instead of 100%" do
        expect(source_file.covered_percent(:branch)).to eq 0.0
      end

      it "reports 0% method coverage instead of 100%" do
        expect(source_file.coverage_statistics[:method].percent).to eq 0.0
      end
    end
  end

  context "with simplecov:disable / enable directives" do
    def build(coverage_data, source_lines)
      file = SimpleCov::SourceFile.new("dummy.rb", coverage_data)
      file.instance_variable_set(:@src, source_lines)
      file
    end

    describe "block disable of line coverage" do
      subject(:source_file) do
        build(
          {"lines" => [1, nil, 5, 5, nil, 1], "branches" => {}, "methods" => {}},
          [
            "x = 1\n",                       # 1
            "# simplecov:disable line\n",    # 2
            "y = 2\n",                       # 3
            "z = 3\n",                       # 4
            "# simplecov:enable line\n",     # 5
            "w = 4\n"                        # 6
          ]
        )
      end

      it "skips lines covered by the directive instead of counting them" do
        expect(source_file.skipped_lines.map(&:line_number)).to eq [2, 3, 4, 5]
        expect(source_file.covered_lines.map(&:line_number)).to eq [1, 6]
        expect(source_file.missed_lines).to eq []
        expect(source_file.covered_strength).to eq 1.0
      end
    end

    describe "inline disable of line coverage" do
      subject(:source_file) do
        build(
          {"lines" => [1, 0, 1], "branches" => {}, "methods" => {}},
          [
            "x = 1\n",
            "raise \"absurd\" # simplecov:disable\n",
            "z = 3\n"
          ]
        )
      end

      it "skips only the trailing line" do
        expect(source_file.skipped_lines.map(&:line_number)).to eq [2]
        expect(source_file.covered_lines.map(&:line_number)).to eq [1, 3]
        expect(source_file.missed_lines).to eq []
      end
    end

    describe "block disable of method coverage" do
      subject(:source_file) do
        build(
          {
            "lines" => [1, nil, 1, nil, nil, 1, nil, nil],
            "branches" => {},
            "methods" => {
              ["Demo", :covered, 1, 0, 3, 3] => 1,
              ["Demo", :method_skipped, 6, 0, 8, 3] => 7
            }
          },
          [
            "def covered\n",                # 1
            "  1\n",                        # 2
            "end\n",                        # 3
            "\n",                           # 4
            "# simplecov:disable method\n", # 5
            "def method_skipped\n",         # 6
            "  1\n",                        # 7
            "end\n"                         # 8
          ]
        )
      end

      it "marks methods overlapping the region as skipped" do
        skipped = source_file.methods.select(&:skipped?)
        expect(skipped.map(&:method_name)).to eq [:method_skipped]
      end

      it "removes skipped methods from covered and missed totals" do
        expect(source_file.covered_methods.map(&:method_name)).to eq [:covered]
        expect(source_file.missed_methods).to eq []
        expect(source_file.covered_strength(:method)).to eq 1.0
      end

      it "leaves the lines themselves alone when only method is disabled" do
        expect(source_file.skipped_lines.map(&:line_number)).to eq []
      end
    end

    describe "block disable of line coverage around a method" do
      subject(:source_file) do
        build(
          {
            "lines" => [nil, 1, 5, nil, nil],
            "branches" => {},
            "methods" => {["Demo", :greet, 2, 0, 4, 3] => 5}
          },
          [
            "# simplecov:disable line\n", # 1
            "def greet\n",                # 2
            "  :hi\n",                    # 3
            "end\n",                      # 4
            "# simplecov:enable line\n"   # 5
          ]
        )
      end

      it "keeps the method in method totals" do
        expect(source_file.methods.map(&:skipped?)).to eq [false]
        expect(source_file.covered_methods.map(&:method_name)).to eq [:greet]
      end

      it "still skips the lines" do
        expect(source_file.skipped_lines.map(&:line_number)).to eq [1, 2, 3, 4, 5]
      end
    end

    describe "deprecated :nocov: block around a method" do
      subject(:source_file) do
        build(
          {
            "lines" => [nil, nil, 0, nil, nil],
            "branches" => {},
            "methods" => {["Demo", :hidden, 2, 0, 4, 3] => 0}
          },
          [
            "# :nocov:\n", # 1
            "def hidden\n", # 2
            "  :hi\n",      # 3
            "end\n",        # 4
            "# :nocov:\n"   # 5
          ]
        )
      end

      before { SimpleCov::SourceFile::SkipChunks.nocov_warned.add("dummy.rb") }

      it "still excludes the method from method totals" do
        expect(source_file.methods.map(&:skipped?)).to eq [true]
        expect(source_file.missed_methods).to eq []
      end
    end

    describe "block disable of branch coverage" do
      subject(:source_file) do
        build(
          {
            "lines" => [nil, 1, 1, nil, 1, nil, nil],
            "branches" => {
              [:if, 0, 2, 0, 6, 3] => {
                [:then, 1, 3, 2, 3, 7] => 1,
                [:else, 2, 5, 2, 5, 7] => 0
              }
            },
            "methods" => {}
          },
          [
            "# simplecov:disable branch\n", # 1
            "if cond\n",                    # 2
            "  :yes\n",                     # 3
            "else\n",                       # 4
            "  :no\n",                      # 5
            "end\n",                        # 6
            "# simplecov:enable branch\n"   # 7
          ]
        )
      end

      it "marks the branches inside the region as skipped" do
        expect(source_file.total_branches).to eq []
        expect(source_file.covered_branches).to eq []
        expect(source_file.missed_branches).to eq []
      end
    end

    describe "branch coverage with an inline directive on the condition line" do
      subject(:source_file) do
        build(
          {
            "lines" => [1, 1, nil, 1, nil],
            "branches" => {
              [:if, 0, 1, 0, 5, 3] => {
                [:then, 1, 2, 2, 2, 7] => 1,
                [:else, 2, 4, 2, 4, 7] => 0
              }
            },
            "methods" => {}
          },
          [
            "if cond # simplecov:disable branch\n", # 1
            "  :yes\n",                              # 2
            "else\n",                                # 3
            "  :no\n",                               # 4
            "end\n"                                  # 5
          ]
        )
      end

      it "skips the :then arm whose report_line falls on the directive, and only that one" do
        expect(source_file.branches.select(&:skipped?).map(&:type)).to eq [:then]
        expect(source_file.branches_report).to eq(3 => [[:else, 0]])
      end
    end

    describe "branch coverage with a directive inside the branch body" do
      subject(:source_file) do
        build(
          {
            "lines" => [1, 1, nil, 1, 1, nil, 1],
            "branches" => {
              [:if, 0, 1, 0, 6, 3] => {
                [:then, 1, 2, 2, 3, 7] => 1,
                [:else, 2, 4, 2, 5, 7] => 0
              }
            },
            "methods" => {}
          },
          [
            "if cond\n", # 1
            "  # simplecov:disable branch\n", # 2
            "  :yes\n",                     # 3
            "else\n",                       # 4
            "  :no\n",                      # 5
            "end\n",                        # 6
            "# simplecov:enable branch\n"   # 7
          ]
        )
      end

      it "skips any branch whose range overlaps the disabled region" do
        expect(source_file.branches.count(&:skipped?)).to eq 2
        expect(source_file.total_branches).to eq []
      end

      it "leaves line classification untouched when only branch is disabled" do
        expect(source_file.skipped_lines).to eq []
      end
    end

    describe "method coverage with a directive inside the method body" do
      subject(:source_file) do
        build(
          {
            "lines" => [1, nil, 1, nil, nil, nil, nil],
            "branches" => {},
            "methods" => {
              ["Demo", :inner_directive, 3, 0, 6, 3] => 0
            }
          },
          [
            "x = 1\n", # 1
            "\n",                             # 2
            "def inner_directive\n",          # 3
            "  # simplecov:disable method\n", # 4
            "  raise 'absurd'\n",             # 5
            "end\n",                          # 6
            "# simplecov:enable method\n"     # 7
          ]
        )
      end

      it "skips the method even though the directive is mid-body" do
        expect(source_file.methods.map(&:skipped?)).to eq [true]
        expect(source_file.covered_methods).to eq []
        expect(source_file.missed_methods).to eq []
      end
    end
  end

  describe "#no_lines?" do
    it "is true for a file whose lines are all `nil` (never)" do
      source_file = described_class.new(source_fixture("never.rb"), CoverageFixtures::NEVER_RB)
      expect(source_file.no_lines?).to be true
    end

    it "is false for a file with at least one relevant line" do
      source_file = described_class.new(source_fixture("sample.rb"), CoverageFixtures::SAMPLE_RB)
      expect(source_file.no_lines?).to be false
    end
  end

  describe "#lines_of_code" do
    it "returns the total relevant line count" do
      source_file = described_class.new(source_fixture("sample.rb"), COVERAGE_FOR_SAMPLE_RB)

      expect(source_file.lines_of_code).to eq(5)
    end

    it "counts nothing when there are no line statistics at all" do
      source_file = described_class.new(source_fixture("sample.rb"), COVERAGE_FOR_SAMPLE_RB)
      allow(source_file).to receive(:coverage_statistics).and_return({})

      expect(source_file.lines_of_code).to eq(0)
    end
  end

  describe "legacy line accessors when :line coverage is disabled" do
    let(:source_file) { described_class.new(source_fixture("sample.rb"), CoverageFixtures::SAMPLE_RB) }

    before do
      allow(source_file).to receive(:coverage_statistics) { |criterion = nil| criterion ? nil : {} }
    end

    it "returns 0 from lines_of_code and nil from covered_percent / covered_strength" do
      expect(source_file.lines_of_code).to eq(0)
      expect(source_file.covered_percent).to be_nil
      expect(source_file.covered_strength).to be_nil
    end
  end

  describe "deprecated percent accessors" do
    let(:source_file) { described_class.new(source_fixture("sample.rb"), CoverageFixtures::SAMPLE_RB) }

    before { allow(SimpleCov::Deprecation).to receive(:warn) }

    it "warns and delegates branches_coverage_percent to covered_percent(:branch)" do
      allow(source_file).to receive(:covered_percent).with(:branch).and_return(42.0)
      expect(source_file.branches_coverage_percent).to eq(42.0)
      expect(SimpleCov::Deprecation).to have_received(:warn).with(
        "`SimpleCov::SourceFile#branches_coverage_percent` is deprecated. Use `covered_percent(:branch)`."
      )
    end

    it "warns and delegates methods_coverage_percent to covered_percent(:method)" do
      allow(source_file).to receive(:covered_percent).with(:method).and_return(50.0)
      expect(source_file.methods_coverage_percent).to eq(50.0)
      expect(SimpleCov::Deprecation).to have_received(:warn).with(
        "`SimpleCov::SourceFile#methods_coverage_percent` is deprecated. Use `covered_percent(:method)`."
      )
    end
  end

  describe SimpleCov::SourceFile::RubyDataParser do
    describe ".parse_array_string" do
      it "handles negative integers via the unary path" do
        expect(described_class.parse_array_string("[1, -2, 3]")).to eq([1, -2, 3])
      end

      it "raises when the input isn't an array literal" do
        expect { described_class.parse_array_string("42") }
          .to raise_error(ArgumentError, %(expected array literal: "42"))
      end

      it "raises when the input carries more than the literal" do
        expect { described_class.parse_array_string("[1]; [2]") }
          .to raise_error(ArgumentError, %(expected array literal: "[1]; [2]"))
      end

      it "raises when the input isn't Ruby at all" do
        expect { described_class.parse_array_string("[") }
          .to raise_error(ArgumentError, %(expected array literal: "["))
      end

      it "raises on a literal outside the grammar, naming the node" do
        expect { described_class.parse_array_string("[1.5]") }
          .to raise_error(ArgumentError, /\Aunexpected element: \[:@float, "1\.5", /)
      end

      {
        "a plain symbol" => ["[:if, 0]", [:if, 0]],
        "a quoted symbol carrying a space" => ['[:"weird name", 1]', [:"weird name", 1]],
        "a quoted symbol carrying an escape" => ['[:"a\\"b", 1]', [:'a"b', 1]],
        "a string class name" => ['["ClassName", :m]', ["ClassName", :m]],
        "a string carrying an escape" => ['["a\\"b", :m]', ['a"b', :m]],
        "a string carrying more than one escape" => ['["a\\"b\\"c", :m]', ['a"b"c', :m]],
        "an empty string" => ['["", :m]', ["", :m]],
        "a bare constant" => ["[Foo, :m]", ["Foo", :m]],
        "a nested constant path" => ["[Foo::Bar, :m]", ["Foo::Bar", :m]],
        "a deeply nested constant path" => ["[Foo::Bar::Baz, :m]", ["Foo::Bar::Baz", :m]],
        "a negative integer" => ["[-2]", [-2]],
        "a zero" => ["[0]", [0]],
        "an empty array" => ["[]", []]
      }.each do |description, (input, expected)|
        it "parses #{description}" do
          expect(described_class.parse_array_string(input)).to eq(expected)
        end
      end

      it "parses an inspect-form singleton class as an opaque string" do
        expect(described_class.parse_array_string("[#<Class:Foo>, :m]")).to eq(["#<Class:Foo>", :m])
      end

      it "parses a singleton class nested inside another" do
        expect(described_class.parse_array_string("[#<Class:#<Object:0x1>>, :m]"))
          .to eq(["#<Class:#<Object:0x1>>", :m])
      end

      it "leaves an already-quoted inspect string alone" do
        expect(described_class.parse_array_string('["#<Class:Foo>", :m]')).to eq(["#<Class:Foo>", :m])
      end

      it "quotes every inspect segment in a key, not just the first" do
        expect(described_class.parse_array_string("[#<Class:Foo>, #<Class:Bar>, :m]"))
          .to eq(["#<Class:Foo>", "#<Class:Bar>", :m])
      end

      it "keeps the quotes inside an inspect segment" do
        expect(described_class.parse_array_string('[#<Struct name="x">, :m]'))
          .to eq(['#<Struct name="x">', :m])
      end
    end

    describe ".call" do
      it "parses a stringified tuple into its array form" do
        expect(described_class.call("[:if, 0, 3, 4, 3, 21]")).to eq([:if, 0, 3, 4, 3, 21])
      end

      it "returns an Array subclass untouched" do
        tuple = Class.new(Array).new([:then, 4, 8])

        expect(described_class.call(tuple)).to be(tuple)
      end

      it "returns arrays untouched and unfrozen" do
        tuple = [:then, 4, 8, 6, 8, 12]

        expect(described_class.call(tuple)).to be(tuple)
        expect(tuple).not_to be_frozen
      end

      it "memoizes string parses, returning one frozen array for equal keys" do
        first = described_class.call("[:while, 1, 5, 2, 7, 5]")
        second = described_class.call(+"[:while, 1, 5, 2, 7, 5]")

        expect(second).to be(first)
        expect(first).to be_frozen
      end

      it "freezes the elements of a cached tuple, not just the tuple itself" do
        tuple = described_class.call('["ClassName", :method1, 2, 2, 5, 5]')

        expect(tuple).to eq(["ClassName", :method1, 2, 2, 5, 5])
        expect(tuple).to all(be_frozen)
      end
    end
  end

  describe "method-coverage round-trip with a dynamic-symbol method name" do
    let(:coverage_data) do
      {
        "methods" => {
          %(["Foo", :"weird name", 1, 0, 3, 5]) => 1
        }
      }
    end

    it "parses the dynamic symbol via the dyna_symbol path" do
      source_file = described_class.new(source_fixture("sample.rb"), coverage_data)
      expect(source_file.methods.map(&:to_s)).to include(/weird name/)
    end
  end

  describe "#coverage_statistics" do
    subject(:source_file) { described_class.new(source_fixture("sample.rb"), COVERAGE_FOR_SAMPLE_RB) }

    it "answers the statistics of the one criterion it is asked for" do
      expect(source_file.coverage_statistics(:line)).to be(source_file.coverage_statistics[:line])
    end

    it "answers nil for a criterion it holds no statistics for" do
      expect(source_file.coverage_statistics(:nope)).to be_nil
    end

    it "builds the statistics once and hands back the same hash" do
      statistics = source_file.coverage_statistics

      expect(source_file.coverage_statistics).to be(statistics)
    end
  end

  describe "#line" do
    subject(:source_file) { described_class.new(source_fixture("sample.rb"), COVERAGE_FOR_SAMPLE_RB) }

    it "numbers lines from one, not from zero" do
      expect(source_file.line(1).source).to eq "# Foo class\n"
      expect(source_file.line(2).source).to eq "class Foo\n"
    end

    it "answers nil past the last line rather than raising" do
      expect(source_file.line(17)).to be_nil
    end
  end

  describe "#real_source_positions" do
    subject(:source_file) do
      described_class.new(source_fixture("branches.rb"), CoverageFixtures::BRANCHES_RB)
    end

    it "reports the branch lines and method names of the parsed source",
       if: SimpleCov::StaticCoverageExtractor.available? do
      expect(source_file.real_source_positions).to eq(branches: Set[3, 5, 7], methods: Set[[:call, 2]])
    end

    it "answers the remembered positions rather than parsing again" do
      positions = {branches: Set[3], methods: Set[[:call, 2]]}
      allow(SimpleCov::StaticCoverageExtractor).to receive(:real_source_positions).and_return(positions)

      source_file.real_source_positions

      expect(source_file.real_source_positions).to be(positions)
    end

    it "parses the source once, remembering even an answer of nil" do
      allow(SimpleCov::StaticCoverageExtractor).to receive(:real_source_positions).and_return(nil)

      2.times { source_file.real_source_positions }

      expect(SimpleCov::StaticCoverageExtractor).to have_received(:real_source_positions).once
    end
  end

  context "when the coverage data holds no line data at all" do
    subject(:source_file) do
      described_class.new(source_fixture("sample.rb"), {"branches" => {}, "methods" => {}})
    end

    it "builds a line for every source row, none of them relevant" do
      expect(source_file.lines.size).to eq 16
      expect(source_file.never_lines.size).to eq 11
      expect(source_file.skipped_lines.size).to eq 5
      expect(source_file.relevant_lines).to eq 0
      expect(source_file.covered_percent).to eq 100.0
    end
  end

  context "when branch coverage data came back from a JSON round-trip" do
    subject(:source_file) do
      described_class.new(source_fixture("branches.rb"), stringified_coverage)
    end

    let(:stringified_coverage) do
      branches = CoverageFixtures::BRANCHES_RB.fetch("branches").to_h do |condition, arms|
        [condition.to_s, arms.transform_keys(&:to_s)]
      end

      CoverageFixtures::BRANCHES_RB.merge("branches" => branches)
    end

    it "parses the keys back and reports what the array keys report" do
      expect(source_file.branches_report).to eq(
        3 => [[:then, 0], [:else, 1]],
        5 => [[:then, 1], [:else, 0]],
        7 => [[:then, 0]],
        9 => [[:else, 1]]
      )
    end
  end

  context "with the eval_generated filters on but no parsed source to check against" do
    let(:source_file) do
      described_class.new(source_fixture("eval_generated.rb"), CoverageFixtures::EVAL_GENERATED_RB)
    end

    around do |example|
      previous_branches = SimpleCov.instance_variable_get(:@ignored_branches)&.dup
      previous_methods = SimpleCov.instance_variable_get(:@ignored_methods)&.dup
      capture_stderr do
        SimpleCov.ignore_branches :eval_generated
        SimpleCov.ignore_methods :eval_generated
      end
      example.run
    ensure
      SimpleCov.instance_variable_set(:@ignored_branches, previous_branches)
      SimpleCov.instance_variable_set(:@ignored_methods, previous_methods)
    end

    before { allow(source_file).to receive(:real_source_positions).and_return(nil) }

    it "keeps every branch" do
      expect(source_file.total_branches.size).to eq 4
    end

    it "keeps every method" do
      expect(source_file.methods.map(&:method_name)).to contain_exactly(:hello, :initialize)
    end
  end

  describe "a branch arm disabled on its own line but reported elsewhere" do
    subject(:source_file) do
      source_file_with(
        {
          "lines" => [1, 1, nil, 1, nil],
          "branches" => {
            [:if, 0, 1, 0, 5, 3] => {
              [:then, 1, 2, 2, 2, 7] => 1,
              [:else, 2, 4, 2, 4, 7] => 0
            }
          },
          "methods" => {}
        },
        [
          "if cond\n",                          # 1
          "  :yes # simplecov:disable\n",       # 2
          "else\n",                             # 3
          "  :no\n",                            # 4
          "end\n"                               # 5
        ]
      )
    end

    it "skips the arm whose range overlaps the directive, and only that one" do
      expect(source_file.branches.select(&:skipped?).map(&:type)).to eq [:then]
      expect(source_file.branches_report).to eq(3 => [[:else, 0]])
    end
  end

  describe SimpleCov::SourceFile::SkipChunks do
    before { described_class.nocov_warned.clear }

    def chunks_for(src, criterion = :line, filename: "chunked.rb")
      chunks = nil
      capture_stderr { chunks = described_class.new(filename, src).for(criterion) }
      chunks
    end

    it "pairs the nocov markers into inclusive ranges of line numbers" do
      src = ["# :nocov:\n", "a = 1\n", "# :nocov:\n", "b = 2\n", "# :nocov:\n", "c = 3\n", "# :nocov:\n"]

      expect(chunks_for(src)).to eq [1..3, 5..7]
    end

    it "runs an unpaired marker to the end of the file" do
      expect(chunks_for(["a = 1\n", "# :nocov:\n", "b = 2\n", "c = 3\n", "d = 4\n"])).to eq [2..5]
    end

    it "finds no chunks in a file that has no markers" do
      expect(chunks_for(["a = 1\n", "b = 2\n"])).to eq []
    end

    it "adds the criterion's own directive ranges to the nocov ones" do
      src = [
        "# :nocov:\n",                  # 1
        "a = 1\n",                      # 2
        "# :nocov:\n",                  # 3
        "# simplecov:disable branch\n", # 4
        "b = 2\n",                      # 5
        "# simplecov:enable branch\n"   # 6
      ]

      expect(chunks_for(src, :branch)).to eq [1..3, 4..6]
      expect(chunks_for(src, :line)).to eq [1..3]
    end

    describe "the nocov deprecation warning" do
      let(:src) { ["a = 1\n", "b = 2\n", "# :nocov:\n", "c = 3\n", "# :nocov:\n"] }

      it "names the file and the first marker's line, and what to write instead" do
        stderr = capture_stderr { described_class.new("warned.rb", src).for(:line) }

        expect(stderr).to eq(
          "warned.rb:3: [DEPRECATION] `# :nocov:` is deprecated and will be removed in a future release. " \
          "Replace with `# simplecov:disable` / `# simplecov:enable` block comments.\n"
        )
      end

      it "warns once per file" do
        capture_stderr { described_class.new("warned.rb", src).for(:line) }
        stderr = capture_stderr { described_class.new("warned.rb", src).for(:line) }

        expect(stderr).to be_empty
      end

      it "warns again for a different file" do
        capture_stderr { described_class.new("warned.rb", src).for(:line) }
        stderr = capture_stderr { described_class.new("other.rb", src).for(:line) }

        expect(stderr).to include("other.rb:3:")
      end

      it "says nothing about a file with no markers" do
        expect(capture_stderr { described_class.new("quiet.rb", ["a = 1\n"]).for(:line) }).to be_empty
      end
    end
  end

  describe SimpleCov::SourceFile::SourceLoader do
    let(:tmpdir) { Dir.mktmpdir("simplecov-source-loader-spec-") }

    after { FileUtils.remove_entry(tmpdir) }

    def source_path(content)
      File.join(tmpdir, "source.rb").tap { |path| File.binwrite(path, content) }
    end

    describe ".call" do
      it "reads every line of a plain file" do
        expect(described_class.call(source_path("a = 1\nb = 2\n"))).to eq ["a = 1\n", "b = 2\n"]
      end

      it "reads no lines out of an empty file" do
        expect(described_class.call(source_path(""))).to eq []
      end

      it "keeps a shebang line and everything under it" do
        expect(described_class.call(source_path("#!/usr/bin/env ruby\na = 1\n")))
          .to eq ["#!/usr/bin/env ruby\n", "a = 1\n"]
      end

      it "reads a file that is nothing but a shebang" do
        expect(described_class.call(source_path("#!/usr/bin/env ruby\n"))).to eq ["#!/usr/bin/env ruby\n"]
      end

      it "replaces invalid bytes on the first line, before any regex sees it" do
        expect(described_class.call(source_path("# caf\xE9\na = 1\n"))).to eq ["# caf�\n", "a = 1\n"]
      end

      it "replaces invalid bytes on the lines below the first" do
        expect(described_class.call(source_path("a = 1\nb = 2\n# caf\xE9\n")))
          .to eq ["a = 1\n", "b = 2\n", "# caf�\n"]
      end

      it "reads a file in the encoding its magic comment declares" do
        expect(described_class.call(source_path("# encoding: EUC-JP\n# \xB0\xA1\n")))
          .to eq ["# encoding: EUC-JP\n", "# 亜\n"]
      end

      it "reads the file as UTF-8 whatever the default external encoding is" do
        path = source_path("# 135°C\n")
        original = Encoding.default_external
        verbose = $VERBOSE
        $VERBOSE = nil

        begin
          Encoding.default_external = Encoding::US_ASCII

          expect(described_class.call(path)).to eq ["# 135°C\n"]
        ensure
          Encoding.default_external = original
          $VERBOSE = verbose
        end
      end

      it "does not run a filename that begins with a pipe" do
        error = Gem.win_platform? ? Errno::EINVAL : Errno::ENOENT
        expect { described_class.call("|echo not-a-file") }.to raise_error(error)
      end
    end

    describe ".scrub_invalid" do
      it "answers nil for nil, which is what an exhausted file hands back" do
        expect(described_class.scrub_invalid(nil)).to be_nil
      end

      it "hands back a valid line untouched" do
        line = +"a = 1\n"

        expect(described_class.scrub_invalid(line)).to be(line)
      end

      it "replaces the invalid bytes of an invalid line" do
        line = (+"# caf\xE9\n").force_encoding(Encoding::UTF_8)

        expect(described_class.scrub_invalid(line)).to eq "# caf�\n"
      end
    end

    describe ".shebang?" do
      it "recognises a shebang at the start of a line" do
        expect(described_class.shebang?("#!/usr/bin/env ruby\n")).to be true
      end

      it "ignores one further along the line" do
        expect(described_class.shebang?("x = 1 #!/usr/bin/env ruby\n")).to be false
      end
    end

    describe ".set_encoding_based_on_magic_comment" do
      it "reads the file in the declared encoding and hands it over as UTF-8" do
        File.open(source_path("# encoding: EUC-JP\n"), "rb:UTF-8") do |file|
          described_class.set_encoding_based_on_magic_comment(file, "# encoding: EUC-JP\n")

          expect(file.external_encoding).to eq Encoding::EUC_JP
          expect(file.internal_encoding).to eq Encoding::UTF_8
        end
      end

      it "leaves the encodings alone for a line that declares nothing" do
        File.open(source_path("a = 1\n"), "rb:UTF-8") do |file|
          described_class.set_encoding_based_on_magic_comment(file, "a = 1\n")

          expect(file.external_encoding).to eq Encoding::UTF_8
          expect(file.internal_encoding).to be_nil
        end
      end
    end

    describe ".ensure_remove_undefs" do
      it "hands back the very array it was given" do
        lines = [+"a = 1\n"]

        expect(described_class.ensure_remove_undefs(lines)).to be(lines)
      end

      it "leaves a valid UTF-8 line exactly as it was" do
        expect(described_class.ensure_remove_undefs([+"# 135°C\n"])).to eq ["# 135°C\n"]
      end

      it "replaces the invalid bytes of a UTF-8 line in place" do
        line = (+"# caf\xE9\n").force_encoding(Encoding::UTF_8)
        described_class.ensure_remove_undefs([line])

        expect(line).to eq "# caf�\n"
      end

      it "transcodes a line that carries another encoding" do
        line = (+"# \xB0\xA1\n").force_encoding(Encoding::EUC_JP)
        described_class.ensure_remove_undefs([line])

        expect(line).to eq "# 亜\n"
        expect(line.encoding).to eq Encoding::UTF_8
      end

      it "replaces bytes that are invalid in the line's own encoding" do
        line = (+"# \x8F\xFF\n").force_encoding(Encoding::EUC_JP)
        described_class.ensure_remove_undefs([line])

        expect(line).to match(/\A# �+\n\z/)
        expect(line).to eq("# ��\n") if RUBY_ENGINE == "ruby"
      end

      it "replaces a character its own encoding has and UTF-8 has not" do
        line = (+"# \x8E\xE0\n").force_encoding(Encoding::EUC_JP)
        described_class.ensure_remove_undefs([line])

        expect(line).to eq "# �\n"
        expect(line.encoding).to eq Encoding::UTF_8
      end

      it "replaces bytes that have no UTF-8 meaning at all" do
        line = (+"# caf\xE9\n").force_encoding(Encoding::BINARY)
        described_class.ensure_remove_undefs([line])

        expect(line).to eq "# caf�\n"
      end
    end
  end
end
