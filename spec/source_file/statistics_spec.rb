# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::SourceFile::Statistics do
  subject(:statistics) { described_class.new(source_file).call }

  let(:covered_line) { instance_double(SimpleCov::SourceFile::Line, coverage: 2) }
  let(:missed_line) { instance_double(SimpleCov::SourceFile::Line, coverage: 0) }
  let(:ignored_line) { instance_double(SimpleCov::SourceFile::Line, coverage: 100) }
  let(:never_line) { instance_double(SimpleCov::SourceFile::Line) }
  let(:covered_branch) { instance_double(SimpleCov::SourceFile::Branch, coverage: 4) }
  let(:missed_branch) { instance_double(SimpleCov::SourceFile::Branch, coverage: 0) }
  let(:covered_method) { instance_double(SimpleCov::SourceFile::Method, coverage: 6) }
  let(:missed_method) { instance_double(SimpleCov::SourceFile::Method, coverage: 0) }

  let(:source_file) do
    instance_double(
      SimpleCov::SourceFile,
      lines: [covered_line, missed_line, ignored_line],
      covered_lines: [covered_line],
      missed_lines: [missed_line],
      never_lines: [never_line],
      covered_branches: [covered_branch],
      missed_branches: [missed_branch],
      covered_methods: [covered_method],
      missed_methods: [missed_method, missed_method],
      not_loaded?: false
    )
  end

  it "excludes ignored lines from line strength" do
    expect(statistics.fetch(:line).strength).to eq(1.0)
  end

  it "calculates branch strength from branch hits" do
    expect(statistics.fetch(:branch).strength).to eq(2.0)
  end

  it "calculates method strength from method hits" do
    expect(statistics.fetch(:method).strength).to eq(2.0)
  end

  context "when a tracked file was not loaded" do
    let(:source_file) do
      instance_double(
        SimpleCov::SourceFile,
        covered_lines: [],
        missed_lines: [],
        never_lines: [],
        covered_branches: [],
        missed_branches: [],
        covered_methods: [],
        missed_methods: [],
        not_loaded?: true
      )
    end

    it "keeps empty branch and method coverage at zero percent and strength" do
      expect(statistics.values_at(:branch, :method)).to all(have_attributes(percent: 0.0, strength: 0.0))
    end
  end
end
