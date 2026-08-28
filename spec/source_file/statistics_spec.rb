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

  it "counts the covered and the missed lines, omitting the never ones" do
    line_statistics = statistics.fetch(:line)

    expect(line_statistics.covered).to eq(1)
    expect(line_statistics.missed).to eq(1)
    expect(line_statistics.total).to eq(2)
    expect(line_statistics.omitted).to eq(1)
    expect(line_statistics.percent).to eq(50.0)
  end

  # Only line coverage has anything to omit: a branch or a method is
  # either counted or not there at all.
  it "counts the branches and the methods, omitting nothing" do
    expect(statistics.fetch(:branch).covered).to eq(1)
    expect(statistics.fetch(:branch).missed).to eq(1)
    expect(statistics.fetch(:branch).omitted).to eq(0)
    expect(statistics.fetch(:method).covered).to eq(1)
    expect(statistics.fetch(:method).missed).to eq(2)
    expect(statistics.fetch(:method).omitted).to eq(0)
  end

  it "reports on every criterion, whichever ones the run measured" do
    expect(statistics.keys).to contain_exactly(:line, :branch, :method)
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

    it "leaves line coverage to the empty-set default" do
      expect(statistics.fetch(:line).percent).to eq(100.0)
    end
  end

  # The zero percent above belongs to unloaded files only. A loaded file
  # with nothing to cover is covered as fully as it can be.
  context "when a loaded file has nothing to cover" do
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
        not_loaded?: false
      )
    end

    it "reports every criterion as fully covered" do
      expect(statistics.values_at(:line, :branch, :method)).to all(have_attributes(percent: 100.0))
    end
  end

  # `Line#coverage` is nullable, so the strength sum coerces rather than
  # raising on an entry that carries no count of its own.
  context "when a covered entry carries no coverage" do
    let(:uncounted_line) { instance_double(SimpleCov::SourceFile::Line, coverage: nil) }

    let(:source_file) do
      instance_double(
        SimpleCov::SourceFile,
        covered_lines: [covered_line, uncounted_line],
        missed_lines: [],
        never_lines: [],
        covered_branches: [],
        missed_branches: [],
        covered_methods: [],
        missed_methods: [],
        not_loaded?: false
      )
    end

    it "counts it as no hits at all" do
      expect(statistics.fetch(:line).strength).to eq(1.0)
    end
  end

  # The zero percent above stands in for data the file never had. A file
  # that does have covered entries keeps the percentage they earned,
  # loaded or not.
  context "when a tracked file was not loaded but has coverage anyway" do
    let(:source_file) do
      instance_double(
        SimpleCov::SourceFile,
        covered_lines: [covered_line],
        missed_lines: [missed_line],
        never_lines: [],
        covered_branches: [covered_branch],
        missed_branches: [missed_branch],
        covered_methods: [covered_method],
        missed_methods: [missed_method],
        not_loaded?: true
      )
    end

    it "keeps the percentage the branches and methods earned" do
      expect(statistics.fetch(:branch).percent).to eq(50.0)
      expect(statistics.fetch(:method).percent).to eq(50.0)
    end
  end
end
