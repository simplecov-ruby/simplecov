# frozen_string_literal: true

require "helper"

describe SimpleCov::SourceFile do
  COVERAGE_FOR_SAMPLE_RB = {
    "lines" =>       [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, 1, 0, nil, nil, nil],
    "branches" => {}
  }.freeze

  COVERAGE_FOR_SAMPLE_RB_WITH_MORE_LINES = {
    "lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, nil, nil, nil, nil, nil, nil]
  }.freeze

  context "a source file initialized with some coverage data" do
    subject do
      SimpleCov::SourceFile.new(source_fixture("sample.rb"), COVERAGE_FOR_SAMPLE_RB)
    end

    it "has a filename" do
      expect(subject.filename).not_to be_nil
    end

    it "has source equal to src" do
      expect(subject.src).to eq(subject.source)
    end

    it "has a project filename which removes the project directory" do
      expect(subject.project_filename).to eq("/spec/fixtures/sample.rb")
    end

    it "has source_lines equal to lines" do
      expect(subject.lines).to eq(subject.source_lines)
    end

    it "has 16 source lines" do
      expect(subject.lines.count).to eq(16)
    end

    it "has all source lines of type SimpleCov::SourceFile::Line" do
      subject.lines.each do |line|
        expect(line).to be_a SimpleCov::SourceFile::Line
      end
    end

    it "has 'class Foo' as line(2).source" do
      expect(subject.line(2).source).to eq("class Foo\n")
    end

    describe "line coverage" do
      it "returns lines number 2, 3, 4, 7 for covered_lines" do
        expect(subject.covered_lines.map(&:line)).to eq([2, 3, 4, 7])
      end

      it "returns lines number 8 for missed_lines" do
        expect(subject.missed_lines.map(&:line)).to eq([8])
      end

      it "returns lines number 1, 5, 6, 9, 10, 16 for never_lines" do
        expect(subject.never_lines.map(&:line)).to eq([1, 5, 6, 9, 10, 16])
      end

      it "returns line numbers 11, 12, 13, 14, 15 for skipped_lines" do
        expect(subject.skipped_lines.map(&:line)).to eq([11, 12, 13, 14, 15])
      end

      it "has 80% covered_percent" do
        expect(subject.covered_percent).to eq(80.0)
      end
    end

    describe "branch coverage" do
      it "has total branches count 0" do
        expect(subject.total_branches.size).to eq(0)
      end

      it "has covered branches count 0" do
        expect(subject.covered_branches.size).to eq(0)
      end

      it "has missed branches count 0" do
        expect(subject.missed_branches.size).to eq(0)
      end

      it "is considered 100% branches covered" do
        expect(subject.branches_coverage_percent).to eq(100.0)
      end

      it "has branch coverage report" do
        expect(subject.branches_report).to eq({})
      end
    end
  end

  context "file with branches" do
    COVERAGE_FOR_BRANCHES_RB = {
      "lines" =>         [1, 1, 1, nil, 1, nil, 1, 0, nil, 1, nil, nil, nil],
      "branches" => {
        [:if, 0, 3, 4, 3, 21] =>
          {[:then, 1, 3, 4, 3, 10] => 0, [:else, 2, 3, 4, 3, 21] => 1},
        [:if, 3, 5, 4, 5, 26] =>
          {[:then, 4, 5, 16, 5, 20] => 1, [:else, 5, 5, 23, 5, 26] => 0},
        [:if, 6, 7, 4, 11, 7] =>
          {[:then, 7, 8, 6, 8, 10] => 0, [:else, 8, 10, 6, 10, 9] => 1}
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("branches.rb"), COVERAGE_FOR_BRANCHES_RB)
    end

    describe "branch coverage" do
      it "has 50% branch coverage" do
        expect(subject.branches_coverage_percent).to eq 50.0
      end

      it "has total branches count 6" do
        expect(subject.total_branches.size).to eq(6)
      end

      it "has covered branches count 3" do
        expect(subject.covered_branches.size).to eq(3)
      end

      it "has missed branches count 3" do
        expect(subject.missed_branches.size).to eq(3)
      end

      it "has coverage report" do
        expect(subject.branches_report).to eq(
          3 => [[:then, 0], [:else, 1]],
          5 => [[:then, 1], [:else, 0]],
          7 => [[:then, 0]],
          9 => [[:else, 1]]
        )
      end

      it "has line 7 with missed branches branch" do
        expect(subject.line_with_missed_branch?(7)).to eq(true)
      end

      it "has line 3 with missed branches branch" do
        expect(subject.line_with_missed_branch?(3)).to eq(true)
      end
    end

    describe "line coverage" do
      it "has line coverage" do
        expect(subject.covered_percent).to be_within(0.01).of(85.71)
      end

      it "has 6 covered lines" do
        expect(subject.covered_lines.size).to eq 6
      end

      it "has 1 missed line" do
        expect(subject.missed_lines.size).to eq 1
      end

      it "has 7 relevant lines" do
        expect(subject.relevant_lines).to eq 7
      end
    end
  end

  context "simulating potential Ruby 1.9 defect -- see Issue #56" do
    subject do
      SimpleCov::SourceFile.new(source_fixture("sample.rb"), COVERAGE_FOR_SAMPLE_RB_WITH_MORE_LINES)
    end

    it "has 16 source lines regardless of extra data in coverage array" do
      # Do not litter test output with known warning
      lines = nil
      expect { lines = subject.lines }.to output.to_stderr
      expect(lines.count).to eq(16)
    end

    it "prints a warning to stderr if coverage array contains more data than lines in the file" do
      expect { subject.lines }.to output(/\AWarning: coverage data provided/).to_stderr
    end
  end

  context "A file that has inline branches" do
    COVERAGE_FOR_INLINE = {
      "lines" =>         [1, 1, 1, nil, 1, 1, 0, nil, 1, nil, nil, nil, nil],
      "branches" => {
        [:if, 0, 3, 11, 3, 33] =>
          {[:then, 1, 3, 23, 3, 27] => 1, [:else, 2, 3, 30, 3, 33] => 0},
        [:if, 3, 6, 6, 10, 9] =>
          {[:then, 4, 7, 8, 7, 12] => 0, [:else, 5, 9, 8, 9, 11] => 1}
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("inline.rb"), COVERAGE_FOR_INLINE)
    end

    it "has branches report on 3 lines" do
      expect(subject.branches_report.keys.size).to eq(3)
      expect(subject.branches_report.keys).to eq([3, 6, 8])
    end

    it "has covered branches count 2" do
      expect(subject.covered_branches.size).to eq(2)
    end

    it "has dual element in condition at line 3 report" do
      expect(subject.branches_report[3]).to eq([[:then, 1], [:else, 0]])
    end

    it "has branches coverage percent 50.00" do
      expect(subject.branches_coverage_percent).to eq(50.00)
    end
  end

  context "a file that is never relevant" do
    COVERAGE_FOR_NEVER_RB = {"lines" => [nil, nil], "branches" => {}}.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("never.rb"), COVERAGE_FOR_NEVER_RB)
    end

    it "has 0.0 covered_strength" do
      expect(subject.covered_strength).to eq 0.0
    end

    it "has 100.0 covered_percent" do
      expect(subject.covered_percent).to eq 100.0
    end

    it "has 100.0 branch coverage" do
      expect(subject.branches_coverage_percent).to eq(100.00)
    end
  end

  context "a file where nothing is ever executed mixed with skipping #563" do
    COVERAGE_FOR_SKIPPED_RB = {"lines" => [nil, nil, nil, nil]}.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("skipped.rb"), COVERAGE_FOR_SKIPPED_RB)
    end

    it "has 0.0 covered_strength" do
      expect(subject.covered_strength).to eq 0.0
    end

    it "has 0.0 covered_percent" do
      expect(subject.covered_percent).to eq 100.0
    end
  end

  context "a file where everything is skipped and missed #563" do
    COVERAGE_FOR_SKIPPED_RB_2 = {"lines" => [nil, nil, 0, nil]}.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("skipped.rb"), COVERAGE_FOR_SKIPPED_RB_2)
    end

    it "has 0.0 covered_strength" do
      expect(subject.covered_strength).to eq 0.0
    end

    it "has 0.0 covered_percent" do
      expect(subject.covered_percent).to eq 100.0
    end

    it "has no covered or missed lines" do
      expect(subject.covered_lines).to be_empty
      expect(subject.missed_lines).to be_empty
    end
  end

  context "a file where everything is skipped/irrelevant but executed #563" do
    COVERAGE_FOR_SKIPPED_AND_EXECUTED_RB = {
      "lines" => [nil, nil, 1, 1, 0, 0, nil, 0, nil, nil, nil, nil],
      "branches" => {
        [:if, 0, 5, 4, 9, 7] =>
          {[:then, 1, 6, 6, 6, 7] => 1, [:else, 2, 8, 6, 8, 7] => 0}
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("skipped_and_executed.rb"), COVERAGE_FOR_SKIPPED_AND_EXECUTED_RB)
    end

    describe "line coverage" do
      it "has no relevant lines" do
        expect(subject.relevant_lines).to eq(0)
      end

      it "has no covered lines" do
        expect(subject.covered_lines.size).to eq(0)
      end

      it "has no missed lines" do
        expect(subject.missed_lines.size).to eq(0)
      end

      it "has a whole lot of skipped lines" do
        expect(subject.skipped_lines.size).to eq(11)
      end

      it "has 0.0 covered_strength" do
        expect(subject.covered_strength).to eq 0.0
      end

      it "has 0.0 covered_percent" do
        expect(subject.covered_percent).to eq 100.0
      end
    end

    describe "branch coverage" do
      it "has an empty branch report" do
        expect(subject.branches_report).to eq({})
      end

      it "has no branches" do
        expect(subject.total_branches.size).to eq 0
        expect(subject.no_branches?).to eq true
      end

      it "does has neither covered nor missed branches" do
        expect(subject.missed_branches.size).to eq 0
        expect(subject.covered_branches.size).to eq 0
      end
    end
  end

  context "a file with more complex skipping" do
    COVERAGE_FOR_NOCOV_COMPLEX_RB = {
      "lines" =>         [nil, nil, 1, 1, nil, 1, nil, nil, nil, 1, nil, nil, 1, nil, nil, 0, nil, 1, nil, 0, nil, nil, 1, nil, nil, nil, nil],
      "branches" => {
        [:if, 0, 6, 4, 11, 7] =>
          {[:then, 1, 7, 6, 7, 7] => 0, [:else, 2, 10, 6, 10, 7] => 1},
        [:if, 3, 13, 4, 13, 24] =>
          {[:then, 4, 13, 4, 13, 12] => 1, [:else, 5, 13, 4, 13, 24] => 0},
        [:while, 6, 16, 4, 16, 27] =>
          {[:body, 7, 16, 4, 16, 12] => 2},
        [:case, 8, 18, 4, 24, 7] => {
          [:when, 9, 20, 6, 20, 11] => 0,
          [:when, 10, 23, 6, 23, 10] => 1,
          [:else, 11, 18, 4, 24, 7] => 0
        }
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("nocov_complex.rb"), COVERAGE_FOR_NOCOV_COMPLEX_RB)
    end

    describe "line coverage" do
      it "has 6 relevant lines" do
        expect(subject.relevant_lines).to eq(5)
      end

      it "has 6 covered lines" do
        expect(subject.covered_lines.size).to eq(5)
      end

      it "has no missed lines" do
        expect(subject.missed_lines.size).to eq(0)
      end

      it "has a whole lot of skipped lines" do
        expect(subject.skipped_lines.size).to eq(11)
      end

      it "has 100.0 covered_percent" do
        expect(subject.covered_percent).to eq 100.0
      end
    end

    describe "branch coverage" do
      it "has an empty branch report" do
        expect(subject.branches_report).to eq(
          9 => [[:else, 1]],
          13 => [[:then, 1], [:else, 0]],
          22 => [[:when, 1]]
        )
      end

      it "covers 3/4 branches" do
        expect(subject.total_branches.size).to eq 4
        expect(subject.missed_branches.size).to eq 1
        expect(subject.covered_branches.size).to eq 3
      end
    end
  end

  context "a file with nested branches" do
    COVERAGE_FOR_NESTED_BRANCHES_RB = {
      "lines" =>         [nil, nil, 1, 1, 1, 1, 1, 1, nil, nil, 0, nil, nil, nil, nil],
      "branches" => {
        [:while, 0, 7, 8, 7, 31] =>
          {[:body, 1, 7, 8, 7, 16] => 2},
        [:if, 2, 6, 6, 9, 9] =>
          {[:then, 3, 7, 8, 8, 11] => 1, [:else, 4, 6, 6, 9, 9] => 0},
        [:if, 5, 5, 4, 12, 7] =>
          {[:then, 6, 6, 6, 9, 9] => 1, [:else, 7, 11, 6, 11, 11] => 0}
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("nested_branches.rb"), COVERAGE_FOR_NESTED_BRANCHES_RB)
    end

    describe "line coverage" do
      it "covers 6/7" do
        expect(subject.covered_percent).to be_within(0.01).of(85.71)
      end
    end

    describe "branch coverage" do
      it "covers 3/5" do
        expect(subject.total_branches.size).to eq 5
        expect(subject.covered_branches.size).to eq 3
        expect(subject.missed_branches.size).to eq 2
      end

      it "registered 2 hits for the while branch" do
        expect(subject.branches_report[7]).to eq [[:body, 2]]
      end
    end
  end

  context "a file with case" do
    COVERAGE_FOR_CASE_STATEMENT_RB = {
      "lines" =>         [1, 1, 1, nil, 0, nil, 1, nil, 0, nil, 0, nil, nil, nil],
      "branches" => {
        [:case, 0, 3, 4, 12, 7] => {
          [:when, 1, 5, 6, 5, 10] => 0,
          [:when, 2, 7, 6, 7, 10] => 1,
          [:when, 3, 9, 6, 9, 10] => 0,
          [:else, 4, 11, 6, 11, 11] => 0
        }
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("case.rb"), COVERAGE_FOR_CASE_STATEMENT_RB)
    end

    describe "line coverage" do
      it "covers 4/7" do
        expect(subject.relevant_lines).to eq 7
        expect(subject.covered_lines.size).to eq 4
        expect(subject.missed_lines.size).to eq 3
      end
    end

    describe "branch coverage" do
      it "covers 1/4" do
        expect(subject.total_branches.size).to eq 4
        expect(subject.covered_branches.size).to eq 1
        expect(subject.missed_branches.size).to eq 3
      end

      it "covers all the things right" do
        expect(subject.branches_report).to eq(
          4 => [[:when, 0]],
          6 => [[:when, 1]],
          8 => [[:when, 0]],
          10 => [[:else, 0]]
        )
      end
    end
  end

  context "a file with case without else" do
    COVERAGE_FOR_CASE_WITHOUT_ELSE_STATEMENT_RB = {
      "lines" =>         [1, 1, 1, nil, 0, nil, 1, nil, 0, nil, nil, nil],
      "branches" => {
        [:case, 0, 3, 4, 10, 7] => {
          [:when, 1, 5, 6, 5, 10] => 0,
          [:when, 2, 7, 6, 7, 10] => 1,
          [:when, 3, 9, 6, 9, 10] => 0,
          [:else, 4, 3, 4, 10, 7] => 0
        }
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("case_without_else.rb"), COVERAGE_FOR_CASE_WITHOUT_ELSE_STATEMENT_RB)
    end

    describe "line coverage" do
      it "covers 4/6" do
        expect(subject.relevant_lines).to eq 6
        expect(subject.covered_lines.size).to eq 4
        expect(subject.missed_lines.size).to eq 2
      end
    end

    describe "branch coverage" do
      it "covers 1/4 (counting the else branch)" do
        expect(subject.total_branches.size).to eq 4
        expect(subject.covered_branches.size).to eq 1
        expect(subject.missed_branches.size).to eq 3
      end

      it "marks the non declared else branch as missing at the point of the case" do
        expect(subject.branches_for_line(3)).to eq [[:else, 0]]
      end

      it "covers the branch that includes 42" do
        expect(subject.branches_report).to eq(
          3 => [[:else, 0]],
          4 => [[:when, 0]],
          6 => [[:when, 1]],
          8 => [[:when, 0]]
        )
      end
    end
  end

  context "a file with if/elsif" do
    COVERAGE_FOR_ELSIF_RB = {
      "lines" => [1, 1, 1, 0, 1, 0, 1, 1, nil, 0, nil, nil, nil],
      "branches" => {
        [:if, 0, 7, 4, 10, 10] =>
          {[:then, 1, 8, 6, 8, 10] => 1, [:else, 2, 10, 6, 10, 10] => 0},
        [:if, 3, 5, 4, 10, 10] =>
          {[:then, 4, 6, 6, 6, 10] => 0, [:else, 5, 7, 4, 10, 10] => 1},
        [:if, 6, 3, 4, 11, 7] =>
          {[:then, 7, 4, 6, 4, 10] => 0, [:else, 8, 5, 4, 10, 10] => 1}
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("elsif.rb"), COVERAGE_FOR_ELSIF_RB)
    end

    describe "line coverage" do
      it "covers 6/9" do
        expect(subject.relevant_lines).to eq 9
        expect(subject.covered_lines.size).to eq 6
        expect(subject.missed_lines.size).to eq 3
      end
    end

    describe "branch coverage" do
      it "covers 3/6" do
        expect(subject.total_branches.size).to eq 6
        expect(subject.covered_branches.size).to eq 3
        expect(subject.missed_branches.size).to eq 3
      end

      it "covers the branch that includes 42" do
        expect(subject.branches_report[7]).to eq [[:then, 1]]
      end
    end
  end

  context "the branch tester script" do
    COVERAGE_FOR_BRANCH_TESTER_RB = {
      "lines" =>         [nil, nil, 1, 1, nil, 1, nil, 1, 1, nil, nil, 1, 0, nil, nil, 1, 0, nil, 1, nil, nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, 1, 1, nil, 0, nil, 1, 1, 0, 0, 1, 5, 0, 0, nil, 0, nil, 0, nil, nil, nil],
      "branches" => {
        [:if, 0, 4, 0, 4, 19] =>
          {[:then, 1, 4, 12, 4, 15] => 0, [:else, 2, 4, 18, 4, 19] => 1},
        [:unless, 3, 6, 0, 6, 23] =>
          {[:else, 4, 6, 0, 6, 23] => 0, [:then, 5, 6, 0, 6, 6] => 1},
        [:unless, 6, 8, 0, 10, 3] =>
          {[:else, 7, 8, 0, 10, 3] => 0, [:then, 8, 9, 2, 9, 14] => 1},
        [:unless, 9, 12, 0, 14, 3] =>
          {[:else, 10, 12, 0, 14, 3] => 1, [:then, 11, 13, 2, 13, 14] => 0},
        [:unless, 12, 16, 0, 20, 3] =>
          {[:else, 13, 19, 2, 19, 13] => 1, [:then, 14, 17, 2, 17, 14] => 0},
        [:if, 15, 22, 0, 22, 19] =>
          {[:then, 16, 22, 0, 22, 6] => 0, [:else, 17, 22, 0, 22, 19] => 1},
        [:if, 18, 23, 0, 25, 3] =>
          {[:then, 19, 24, 2, 24, 14] => 1, [:else, 20, 23, 0, 25, 3] => 0},
        [:if, 21, 27, 0, 29, 3] =>
          {[:then, 22, 28, 2, 28, 14] => 0, [:else, 23, 27, 0, 29, 3] => 1},
        [:if, 24, 31, 0, 35, 3] =>
          {[:then, 25, 32, 2, 32, 14] => 1, [:else, 26, 34, 2, 34, 13] => 0},
        [:if, 27, 42, 0, 47, 8] =>
          {[:then, 28, 43, 2, 45, 13] => 0, [:else, 29, 47, 2, 47, 8] => 0},
        [:if, 30, 40, 0, 47, 8] =>
          {[:then, 31, 41, 2, 41, 25] => 1, [:else, 32, 42, 0, 47, 8] => 0},
        [:if, 33, 37, 0, 48, 3] =>
          {[:then, 34, 38, 2, 39, 21] => 0, [:else, 35, 40, 0, 47, 8] => 1}
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("branch_tester_script.rb"), COVERAGE_FOR_BRANCH_TESTER_RB)
    end

    describe "line coverage" do
      it "covers 18/28" do
        expect(subject.relevant_lines).to eq 28
        expect(subject.covered_lines.size).to eq 18
      end
    end

    describe "branch coverage" do
      it "covers 10/24" do
        expect(subject.total_branches.size).to eq 24
        expect(subject.covered_branches.size).to eq 11
      end

      it "notifies us of the missing else branch on line 27 that's hit" do
        expect(subject.branches_report[27]).to eq [[:then, 0], [:else, 1]]
      end
    end
  end

  context "a file entirely ignored with a single # :nocov:" do
    COVERAGE_FOR_SINGLE_NOCOV_RB = {
      "lines" => [nil, 1, 1, 1, 0, 1, 0, 1, 1, nil, 0, nil, nil, nil],
      "branches" => {
        [:if, 0, 8, 4, 11, 10] =>
          {[:then, 1, 9, 6, 9, 10] => 1, [:else, 2, 11, 6, 11, 10] => 0},
        [:if, 3, 6, 4, 11, 10] =>
          {[:then, 4, 7, 6, 7, 10] => 0, [:else, 5, 8, 4, 11, 10] => 1},
        [:if, 6, 4, 4, 12, 7] =>
          {[:then, 7, 5, 6, 5, 10] => 0, [:else, 8, 6, 4, 11, 10] => 1}
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("single_nocov.rb"), COVERAGE_FOR_SINGLE_NOCOV_RB)
    end

    describe "line coverage" do
      it "has all lines skipped" do
        expect(subject.skipped_lines.size).to eq(subject.lines.size)
        expect(subject.skipped_lines.size).to eq(14)
      end

      it "reports 100% coverage on 0/0" do
        expect(subject.covered_percent).to eq 100.0
        expect(subject.relevant_lines).to eq 0
        expect(subject.covered_lines.size).to eq 0
      end
    end

    describe "branch coverage" do
      it "has 100% branch coverage on 0/0" do
        branch_coverage = subject.coverage_statistics.fetch(:branch)

        expect(branch_coverage.percent).to eq 100.0
        expect(branch_coverage.total).to eq 0
        expect(branch_coverage.covered).to eq 0
      end

      it "has all branches marked as skipped" do
        expect(subject.branches.all?(&:skipped?)).to eq true
      end
    end
  end

  context "a file with an uneven usage of # :nocov:s" do
    COVERAGE_FOR_UNEVEN_NOCOV_RB = {
      "lines" => [1, 1, nil, 1, 0, 1, 0, nil, 1, 1, nil, nil, 0, nil, nil, nil],
      "branches" => {
        [:if, 0, 9, 4, 13, 10] =>
          {[:then, 1, 10, 6, 10, 10] => 1, [:else, 2, 13, 6, 13, 10] => 0},
        [:if, 3, 6, 4, 13, 10] =>
          {[:then, 4, 7, 6, 7, 10] => 0, [:else, 5, 9, 4, 13, 10] => 1},
        [:if, 6, 4, 4, 14, 7] =>
          {[:then, 7, 5, 6, 5, 10] => 0, [:else, 8, 6, 4, 13, 10] => 1}
      }
    }.freeze

    subject do
      SimpleCov::SourceFile.new(source_fixture("uneven_nocovs.rb"), COVERAGE_FOR_UNEVEN_NOCOV_RB)
    end

    describe "line coverage" do
      it "has 12 lines skipped" do
        expect(subject.skipped_lines.size).to eq(12)
      end

      it "reports 100% coverage on 4/4" do
        expect(subject.covered_percent).to eq 100.0
        expect(subject.relevant_lines).to eq 4
        expect(subject.covered_lines.size).to eq 4
      end
    end

    describe "branch coverage" do
      it "has 100% branch coverage on 1/1" do
        branch_coverage = subject.coverage_statistics.fetch(:branch)

        expect(branch_coverage.percent).to eq 100.0
        expect(branch_coverage.total).to eq 1
        expect(branch_coverage.covered).to eq 1
      end

      it "has 5 branches marked as skipped" do
        expect(subject.branches.select(&:skipped?).size).to eq 5
      end
    end
  end

  context "a file contains non-ASCII characters" do
    COVERAGE_FOR_SINGLE_LINE = {"lines" => [nil]}.freeze
    COVERAGE_FOR_DOUBLE_LINES = {"lines" => [nil, 1]}.freeze
    COVERAGE_FOR_TRIPLE_LINES = {"lines" => [nil, nil, 1]}.freeze
    DEGREE_135_LINE = "puts \"135°C\"\n"

    shared_examples_for "converting to UTF-8" do
      it "has all source lines of encoding UTF-8" do
        subject.lines.each do |line|
          expect(line.source.encoding).to eq(Encoding::UTF_8)
          expect(line.source).to be_valid_encoding
        end
      end
    end

    describe "UTF-8 without magic comment" do
      subject do
        SimpleCov::SourceFile.new(source_fixture("utf-8.rb"), COVERAGE_FOR_SINGLE_LINE)
      end

      it_behaves_like "converting to UTF-8"

      it "has the line with 135°C" do
        expect(subject.line(1).source).to eq DEGREE_135_LINE
      end
    end

    describe "UTF-8 with magic comment" do
      subject do
        SimpleCov::SourceFile.new(source_fixture("utf-8-magic.rb"), COVERAGE_FOR_DOUBLE_LINES)
      end

      it_behaves_like "converting to UTF-8"

      it "has the line with 135°C" do
        expect(subject.line(2).source).to eq DEGREE_135_LINE
      end
    end

    describe "EUC-JP with magic comment" do
      subject do
        SimpleCov::SourceFile.new(source_fixture("euc-jp.rb"), COVERAGE_FOR_DOUBLE_LINES)
      end

      it_behaves_like "converting to UTF-8"

      it "has the line with 135°C" do
        expect(subject.line(2).source).to eq DEGREE_135_LINE
      end
    end

    describe "EUC-JP with magic comment and shebang" do
      subject do
        SimpleCov::SourceFile.new(source_fixture("euc-jp-shebang.rb"), COVERAGE_FOR_TRIPLE_LINES)
      end

      it_behaves_like "converting to UTF-8"

      it "has all the right lines" do
        expect(subject.lines.map(&:source)).to eq [
          "#!/usr/bin/env ruby\n",
          "# encoding: EUC-JP\n",
          DEGREE_135_LINE
        ]
      end
    end

    describe "empty euc-jp file" do
      subject do
        SimpleCov::SourceFile.new(source_fixture("empty_euc-jp.rb"), "lines" => [])
      end

      it "has empty lines" do
        expect(subject.lines).to be_empty
      end
    end
  end
end
