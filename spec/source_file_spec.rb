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

RSpec.describe SimpleCov::SourceFile do
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
        expect(source_file.branches_coverage_percent).to eq(100.0)
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
        expect(source_file.methods_coverage_percent).to eq(100.0)
      end
    end
  end

  context "when file with methods" do
    subject(:source_file) do
      described_class.new(source_fixture("methods.rb"), coverage_for_methods_rb)
    end

    let(:coverage_for_methods_rb) do
      {
        "lines" => [1, 1, 1, 1, nil, nil, 1, nil, 1, 1, nil, nil, 1, 0, nil, nil, nil, 1],
        "branches" => {},
        "methods" => {
          ["A", :method1, 2, 2, 5, 5] => 1,
          ["A", :method2, 9, 2, 11, 5] => 1,
          ["A", :method3, 13, 2, 15, 5] => 0
        }
      }
    end

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
        expect(source_file.methods_coverage_percent).to eq(66.66666666666667)
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
      # Simulates what happens after JSON.parse(JSON.dump(...)):
      # Array keys become their string representation
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
      # When Ruby's Coverage API returns a class object (not a string) as the
      # first element of a method key, JSON round-trip produces an unquoted
      # class name like [A, :method1, 2, 2, 5, 5] instead of ["A", :method1, ...]
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
  end

  # Regression: coverage data can have "branches" => nil when another gem
  # interferes with Coverage, or .resultset.json contains "branches": null.
  # Hash#fetch returns nil (not the default {}) when the key exists with nil value.
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
      expect(source_file.branches_coverage_percent).to eq 100.0
    end
  end

  context "when file with branches" do
    subject(:source_file) do
      described_class.new(source_fixture("branches.rb"), CoverageFixtures::BRANCHES_RB)
    end

    describe "branch coverage" do
      it "has 50% branch coverage" do
        expect(source_file.branches_coverage_percent).to eq 50.0
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
      expect(source_file.branches_coverage_percent).to eq(50.00)
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
      expect(source_file.branches_coverage_percent).to eq(100.00)
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

    before { described_class.nocov_warned.clear }

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
        expect(source_file.branches_coverage_percent).to eq 0.0
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
              ["Demo", :method_skipped, 6, 0, 8, 3] => 0
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
      end

      it "leaves the lines themselves alone when only method is disabled" do
        # The method's body lines (6..8) should not be marked skipped solely
        # because of `simplecov:disable method`.
        expect(source_file.skipped_lines.map(&:line_number)).to eq []
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
      # The directive sits on the `if` line itself. The :then arm's source
      # range starts on the next line (`:yes`), so a pure overlap check would
      # miss it. The arm's `report_line` is the condition line, which is
      # where the user typed the directive — process_skipped_branches honours
      # report_line membership in addition to range overlap.
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

      it "skips the :then arm whose report_line falls on the directive" do
        skipped = source_file.branches.select(&:skipped?)
        expect(skipped.map(&:type)).to include(:then)
      end
    end

    describe "branch coverage with a directive inside the branch body" do
      # A `# simplecov:disable branch` placed inside a single arm of an `if`
      # should still mark the enclosing branch as skipped, because the branch's
      # source range (start..end) overlaps the disabled range.
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
      # The directive at line 4 sits inside a method spanning lines 3..6.
      # `Method#overlaps_with?` should detect the intersection and skip the
      # method even though the directive isn't on the method's start line.
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
      source_file = described_class.new(source_fixture("sample.rb"), CoverageFixtures::SAMPLE_RB)
      expect(source_file.lines_of_code).to be > 0
    end
  end

  describe "legacy line accessors when :line coverage is disabled" do
    # When line coverage is off, `coverage_statistics` doesn't include
    # a `:line` key, so the legacy accessors should return nil/0 rather
    # than crashing on `nil.percent` / `nil.total`.
    let(:source_file) { described_class.new(source_fixture("sample.rb"), CoverageFixtures::SAMPLE_RB) }

    before { allow(source_file).to receive(:coverage_statistics).and_return({}) }

    it "returns 0 from lines_of_code and nil from covered_percent / covered_strength" do
      expect(source_file.lines_of_code).to eq(0)
      expect(source_file.covered_percent).to be_nil
      expect(source_file.covered_strength).to be_nil
    end
  end

  describe "parse_ruby_array_string edge cases" do
    let(:source_file) { described_class.new(source_fixture("sample.rb"), CoverageFixtures::SAMPLE_RB) }

    it "handles negative integers via the unary path" do
      expect(source_file.send(:parse_ruby_array_string, "[1, -2, 3]")).to eq([1, -2, 3])
    end

    it "raises when the input isn't an array literal" do
      expect { source_file.send(:parse_ruby_array_string, "42") }.to raise_error(ArgumentError, /array literal/)
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
end
