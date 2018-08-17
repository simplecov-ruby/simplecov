# frozen_string_literal: true

require "helper"

if SimpleCov.usable?
  describe SimpleCov::SourceFile do
    COVERAGE_FOR_SAMPLE_RB = {
      :lines => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, nil, nil, nil, nil, nil],
      :branches => {[:if, 0, 17, 6, 23, 9] => {[:then, 1, 18, 8, 18, 81] => 3, [:else, 2, 20, 8, 22, 19] => 0}, [:if, 3, 29, 6, 35, 9] => {[:then, 4, 30, 8, 30, 81] => 3, [:else, 5, 32, 8, 34, 20] => 0}},
    }.freeze

    COVERAGE_FOR_SAMPLE_RB_WITH_MORE_LINES = {
      :lines => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, nil, nil, nil, nil, nil, nil],
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

      it "Has total branches count 4" do
        expect(subject.total_branches.size).to eq(4)
      end

      it "Has covered branches count 2" do
        expect(subject.covered_branches.size).to eq(2)
      end

      it "Has missed branches count 2" do
        expect(subject.missed_branches.size).to eq(2)
      end

      it "Has root branches count 2" do
        expect(subject.root_branches.size).to eq(2)
      end

      it "Has branch on line number 7 with report pr line" do
        expect(subject.branch_per_line(17)).to eq("[3, \"+\"]")
      end

      it "Has coverage report" do
        expect(subject.branches_report).to eq(17 => [[3, "+"]], 19 => [[0, "-"]], 29 => [[3, "+"]], 31 => [[0, "-"]])
      end

      it "Hash line 31 with missed branches" do
        expect(subject.line_with_missed_branch?(31)).to eq(true)
      end
    end

    context "simulating potential Ruby 1.9 defect -- see Issue #56" do
      subject do
        SimpleCov::SourceFile.new(source_fixture("sample.rb"), COVERAGE_FOR_SAMPLE_RB_WITH_MORE_LINES)
      end

      it "has 16 source lines regardless of extra data in coverage array" do
        # Do not litter test output with known warning
        capture_stderr { expect(subject.lines.count).to eq(16) }
      end

      it "prints a warning to stderr if coverage array contains more data than lines in the file" do
        captured_output = capture_stderr do
          subject.lines
        end

        expect(captured_output).to match(/^Warning: coverage data provided/)
      end
    end

    context "A file that have inline branches" do
      COVERAGE_FOR_DUMB_INLINE = {
        :lines => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, nil, nil, nil, nil, nil],
        :branches => {[:if, 0, 18, 6, 18, 9] => {[:then, 1, 18, 8, 18, 81] => 3, [:else, 2, 18, 8, 19, 19] => 0}, [:if, 3, 29, 6, 35, 9] => {[:then, 4, 30, 8, 30, 81] => 3, [:else, 5, 31, 8, 34, 20] => 0}},
      }.freeze

      subject do
        SimpleCov::SourceFile.new(source_fixture("never.rb"), COVERAGE_FOR_DUMB_INLINE)
      end

      it "Has branches report on 3 lines " do
        expect(subject.branches_report.keys.size).to eq(3)
        expect(subject.branches_report.keys).to eq([18, 29, 30])
      end

      it "Has covered branches count 2 " do
        expect(subject.covered_branches.size).to eq(2)
      end

      it "Has dual element in condition at line 18 report" do
        expect(subject.branches_report[18]).to eq([[3, "+"], [0, "-"]])
      end

      it "Has branches coverage precent 50.00" do
        expect(subject.branches_coverage_precent).to eq(50.00)
      end
    end

    context "a file that is never relevant" do
      COVERAGE_FOR_NEVER_RB = {
        :lines => [nil, nil],
      }.freeze

      subject do
        SimpleCov::SourceFile.new(source_fixture("never.rb"), COVERAGE_FOR_NEVER_RB)
      end

      it "has 0.0 covered_strength" do
        expect(subject.covered_strength).to eq 0.0
      end

      it "has 0.0 covered_percent" do
        expect(subject.covered_percent).to eq 100.0
      end
    end

    context "a file where nothing is ever executed mixed with skipping #563" do
      COVERAGE_FOR_SKIPPED_RB = {
        :lines => [nil, nil, nil, nil],
      }.freeze

      subject do
        SimpleCov::SourceFile.new(source_fixture("skipped.rb"), COVERAGE_FOR_SKIPPED_RB)
      end

      it "has 0.0 covered_strength" do
        expect(subject.covered_strength).to eq 0.0
      end

      it "has 0.0 covered_percent" do
        expect(subject.covered_percent).to eq 0.0
      end
    end

    context "a file where everything is skipped and missed #563" do
      COVERAGE_FOR_SKIPPED_RB_2 = {
        :lines => [nil, nil, 0, nil],
      }.freeze

      subject do
        SimpleCov::SourceFile.new(source_fixture("skipped.rb"), COVERAGE_FOR_SKIPPED_RB_2)
      end

      it "has 0.0 covered_strength" do
        expect(subject.covered_strength).to eq 0.0
      end

      it "has 0.0 covered_percent" do
        expect(subject.covered_percent).to eq 0.0
      end
    end

    context "a file where everything is skipped/irrelevamt but executed #563" do
      COVERAGE_FOR_SKIPPED_AND_EXECUTED_RB = {
        :lines => [nil, nil, 1, 1, 0, nil, nil, nil],
      }.freeze

      subject do
        SimpleCov::SourceFile.new(source_fixture("skipped_and_executed.rb"), COVERAGE_FOR_SKIPPED_AND_EXECUTED_RB)
      end

      it "has 0.0 covered_strength" do
        expect(subject.covered_strength).to eq 0.0
      end

      it "has 0.0 covered_percent" do
        expect(subject.covered_percent).to eq 0.0
      end
    end
  end
end
