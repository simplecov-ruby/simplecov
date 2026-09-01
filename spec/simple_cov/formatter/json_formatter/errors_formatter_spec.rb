# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Formatter::JSONFormatter::ErrorsFormatter,
  mutant_expression: "SimpleCov::Formatter::JSONFormatter*" do
  let(:line_stats) { SimpleCov::CoverageStatistics.new(covered: 9, missed: 1) }
  let(:branch_stats) { SimpleCov::CoverageStatistics.new(covered: 1, missed: 1) }
  let(:method_stats) { SimpleCov::CoverageStatistics.new(covered: 3, missed: 1) }
  let(:all_statistics) { {line: line_stats, branch: branch_stats, method: method_stats} }

  let(:a_file) { file_double("lib/a.rb", all_statistics) }
  let(:b_file) { file_double("lib/b.rb", {line: SimpleCov::CoverageStatistics.new(covered: 1, missed: 3)}) }

  let(:result) { result_double(a_file) }

  before do
    allow(SimpleCov).to receive_messages(
      minimum_coverage: {}, minimum_coverage_by_file: {}, minimum_coverage_by_file_overrides: {},
      minimum_coverage_by_group: {}, maximum_coverage: {}, maximum_coverage_drop: {},
      maximum_missed: {}, maximum_missed_per_file: {}, maximum_missed_per_file_overrides: {},
      baseline: nil
    )
    allow(SimpleCov::LastRun).to receive(:read).and_return(nil)
  end

  it "reports an empty hash when no threshold is configured" do
    expect(described_class.call(result)).to eq({})
  end

  it "builds a fresh hash for every call" do
    allow(SimpleCov).to receive(:minimum_coverage).and_return({line: 95}, {})

    expect([described_class.call(result), described_class.call(result)])
      .to eq([{minimum_coverage: {lines: {expected: 95, actual: 90.0}}}, {}])
  end

  context "when every criterion sits below the overall minimum" do
    before { allow(SimpleCov).to receive(:minimum_coverage).and_return(line: 95, branch: 60, method: 80) }

    it "reports each of them under its report-facing key" do
      expect(described_class.call(result)).to eq(minimum_coverage: {
        lines: {expected: 95, actual: 90.0},
        branches: {expected: 60, actual: 50.0},
        methods: {expected: 80, actual: 75.0}
      })
    end
  end

  it "reports a violation keyed on :oneshot_line under lines" do
    allow(SimpleCov).to receive(:minimum_coverage).and_return(oneshot_line: 95)

    expect(described_class.call(result)).to eq(minimum_coverage: {lines: {expected: 95, actual: 90.0}})
  end

  it "reports every file and criterion below the per-file minimum" do
    allow(SimpleCov).to receive(:minimum_coverage_by_file).and_return(line: 95, branch: 60)

    expect(described_class.call(result_double(a_file, b_file))).to eq(minimum_coverage_by_file: {
      "lib/a.rb" => {lines: {expected: 95, actual: 90.0}, branches: {expected: 60, actual: 50.0}},
      "lib/b.rb" => {lines: {expected: 95, actual: 25.0}}
    })
  end

  it "reports a per-file minimum raised by a path override" do
    allow(SimpleCov).to receive_messages(minimum_coverage_by_file: {line: 80},
      minimum_coverage_by_file_overrides: {"lib/a.rb" => {line: 95}})

    expect(described_class.call(result)).to eq(minimum_coverage_by_file: {"lib/a.rb" => {lines: {expected: 95, actual: 90.0}}})
  end

  it "reports a baseline violation with the missed counts the floor was judged by" do
    allow(SimpleCov).to receive(:baseline).and_return(baseline("lib/a.rb" => {line: floor(95.0, 0), branch: floor(75.0, nil)}))

    expect(described_class.call(result)).to eq(baseline: {"lib/a.rb" => {
      lines: {expected: 95.0, actual: 90.0, actual_missed: 1, allowed_missed: 0},
      branches: {expected: 75.0, actual: 50.0, actual_missed: 1}
    }})
  end

  it "exempts a file with a baseline floor from the per-file minimum" do
    allow(SimpleCov).to receive_messages(
      minimum_coverage_by_file: {line: 95},
      baseline: baseline("lib/a.rb" => {line: floor(80.0, nil)})
    )

    expect(described_class.call(result)).to eq({})
  end

  it "reports every criterion below a group's minimum under the group name" do
    group = instance_double(SimpleCov::FileList, coverage_statistics: {line: line_stats, branch: branch_stats})
    allow(SimpleCov).to receive(:minimum_coverage_by_group).and_return("Models" => {line: 95, branch: 60})

    expect(described_class.call(result_double(a_file, groups: {"Models" => group}))).to eq(minimum_coverage_by_group: {
      "Models" => {lines: {expected: 95, actual: 90.0}, branches: {expected: 60, actual: 50.0}}
    })
  end

  it "reports every criterion above the overall maximum" do
    allow(SimpleCov).to receive(:maximum_coverage).and_return(line: 85, method: 70)

    expect(described_class.call(result)).to eq(maximum_coverage: {
      lines: {expected: 85, actual: 90.0},
      methods: {expected: 70, actual: 75.0}
    })
  end

  it "reports a drop past the maximum against the last run" do
    allow(SimpleCov).to receive(:maximum_coverage_drop).and_return(line: 2)
    allow(SimpleCov::LastRun).to receive(:read).and_return({result: {line: 95.0}})

    expect(described_class.call(result)).to eq(maximum_coverage_drop: {lines: {maximum: 2, actual: 5.0}})
  end

  it "reports every criterion over the overall missed cap" do
    allow(SimpleCov).to receive(:maximum_missed).and_return(line: 0, branch: 0)

    expect(described_class.call(result)).to eq(maximum_missed: {
      lines: {maximum: 0, actual: 1},
      branches: {maximum: 0, actual: 1}
    })
  end

  it "reports every file and criterion over the per-file missed cap" do
    allow(SimpleCov).to receive(:maximum_missed_per_file).and_return(line: 0, branch: 0)

    expect(described_class.call(result_double(a_file, b_file))).to eq(maximum_missed_per_file: {
      "lib/a.rb" => {lines: {maximum: 0, actual: 1}, branches: {maximum: 0, actual: 1}},
      "lib/b.rb" => {lines: {maximum: 0, actual: 3}}
    })
  end

  it "reports a per-file missed cap introduced by a path override" do
    allow(SimpleCov).to receive(:maximum_missed_per_file_overrides).and_return("lib/a.rb" => {line: 0})

    expect(described_class.call(result)).to eq(maximum_missed_per_file: {"lib/a.rb" => {lines: {maximum: 0, actual: 1}}})
  end

  it "exempts a file with a baseline floor from the per-file missed cap" do
    allow(SimpleCov).to receive_messages(
      maximum_missed_per_file: {line: 0},
      baseline: baseline("lib/a.rb" => {line: floor(80.0, nil)})
    )

    expect(described_class.call(result)).to eq({})
  end

  it "keeps one section per family when several thresholds are tripped" do
    allow(SimpleCov).to receive_messages(minimum_coverage: {line: 95}, maximum_missed: {line: 0})

    expect(described_class.call(result)).to eq(
      minimum_coverage: {lines: {expected: 95, actual: 90.0}},
      maximum_missed: {lines: {maximum: 0, actual: 1}}
    )
  end

  def file_double(project_filename, statistics)
    instance_double(SimpleCov::SourceFile,
      filename: "/project/#{project_filename}",
      project_filename: project_filename,
      coverage_statistics: statistics)
  end

  def result_double(*files, groups: {})
    instance_double(SimpleCov::Result, files: files, coverage_statistics: all_statistics, groups: groups)
  end

  def baseline(entries)
    SimpleCov::Baseline.new(entries)
  end

  def floor(percent, missed)
    SimpleCov::Baseline::Floor.new(percent: percent, missed: missed)
  end
end
