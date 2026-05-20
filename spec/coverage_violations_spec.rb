# frozen_string_literal: true

require "helper"

# Focuses on the "criterion configured but not measured" path that the
# strict profile relies on for JRuby — `enable_coverage :branch` is
# accepted on every engine, but JRuby's Coverage doesn't actually emit
# branch data, so the criterion ends up in the thresholds hash with no
# stats to check against. The runtime check skips silently rather than
# `fetch`-raising.
RSpec.describe SimpleCov::CoverageViolations do
  let(:line_stats)   { SimpleCov::CoverageStatistics.new(covered: 80, missed: 20) }
  let(:branch_stats) { SimpleCov::CoverageStatistics.new(covered: 5,  missed: 5) }

  describe ".minimum_overall" do
    it "reports violations for criteria below threshold" do
      result = instance_double(SimpleCov::Result, coverage_statistics: {line: line_stats, branch: branch_stats})
      violations = described_class.minimum_overall(result, line: 90)
      expect(violations).to contain_exactly(criterion: :line, expected: 90, actual: 80.0)
    end

    it "skips a configured threshold whose criterion isn't in the stats" do
      # No :branch key in coverage_statistics — simulates JRuby's "branch
      # criterion enabled but not measurable" state.
      result = instance_double(SimpleCov::Result, coverage_statistics: {line: line_stats})
      violations = described_class.minimum_overall(result, line: 100, branch: 100)
      expect(violations).to contain_exactly(criterion: :line, expected: 100, actual: 80.0)
    end
  end

  describe ".minimum_by_file" do
    let(:file) do
      instance_double(SimpleCov::SourceFile,
                      filename: "/abs/lib/a.rb",
                      project_filename: "lib/a.rb",
                      coverage_statistics: {line: line_stats})
    end

    it "skips a configured threshold whose criterion isn't in the file's stats" do
      result = instance_double(SimpleCov::Result, files: [file])
      violations = described_class.minimum_by_file(result, line: 100, branch: 100)
      expect(violations.map { |v| v[:criterion] }).to contain_exactly(:line)
    end
  end

  describe ".minimum_by_group" do
    let(:group) { instance_double(SimpleCov::FileList, coverage_statistics: {line: line_stats}) }

    it "skips a configured threshold whose criterion isn't in the group's stats" do
      result = instance_double(SimpleCov::Result, groups: {"Models" => group})
      violations = described_class.minimum_by_group(result, "Models" => {line: 100, branch: 100})
      expect(violations.map { |v| v[:criterion] }).to contain_exactly(:line)
    end
  end

  describe ".maximum_drop" do
    it "skips a configured drop check whose criterion isn't in the stats" do
      result = instance_double(SimpleCov::Result, coverage_statistics: {line: line_stats})
      # last_run records all three; current only has :line. The :branch
      # drop check should silently skip rather than crash.
      last_run = {result: {line: 90.0, branch: 90.0}}
      violations = described_class.maximum_drop(result, {line: 5, branch: 5}, last_run: last_run)
      expect(violations.map { |v| v[:criterion] }).to contain_exactly(:line)
    end
  end
end
