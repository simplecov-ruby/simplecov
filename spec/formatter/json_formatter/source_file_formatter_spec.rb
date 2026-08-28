# frozen_string_literal: true

require "helper"

# Direct examples for the per-file payload. Reached through a whole
# formatted document these values have already been through JSON, where
# a Symbol and its String spelling are the same two bytes and an object
# that is not a String is serialized by calling `to_s` on it anyway.
# Comparing the built hash is what tells those apart.
#
# `mutant_expression` keeps these examples in the pool the whole
# JSONFormatter namespace shares, rather than claiming the
# SourceFileFormatter pool for this file alone.
RSpec.describe SimpleCov::Formatter::JSONFormatter::SourceFileFormatter,
               mutant_expression: "SimpleCov::Formatter::JSONFormatter*" do
  # Expanded, because the context lookup expands what it is asked for
  # and a bare "/project" path gains a drive letter on Windows.
  let(:filename) { File.expand_path("/project/lib/a.rb") }

  # Every line state the payload distinguishes: never, covered, skipped
  # (which reports as "ignored" rather than as a count), and missed. The
  # trailing newlines are the ones the source array has to strip.
  let(:lines) do
    [
      line("# a comment\n", 1, nil),
      line("def bar\n", 2, 2),
      line("  x = 1 if y\n", 3, 2),
      line("  hidden\n", 4, 1, skipped: true),
      line("def baz\n", 5, 0),
      line("end\n", 6, nil)
    ]
  end

  # An inline branch and a block one, because the payload reports
  # `inline` and derives `report_line` from it.
  let(:inline_branch) do
    SimpleCov::SourceFile::Branch.new(start_line: 3, end_line: 3, coverage: 2, inline: true, type: :then)
  end
  let(:block_branch) do
    SimpleCov::SourceFile::Branch.new(start_line: 5, end_line: 6, coverage: 0, inline: false, type: :else)
  end

  # A method reads its lines back off the file to decide whether it was
  # skipped, so it gets a plain reader rather than the double it is
  # itself stubbed on.
  let(:line_source) { instance_double(SimpleCov::SourceFile, lines: lines) }
  let(:covered_method) { SimpleCov::SourceFile::Method.new(line_source, ["Foo", :bar, 2, 2, 3, 5], 2) }
  let(:missed_method) { SimpleCov::SourceFile::Method.new(line_source, ["Foo", :baz, 5, 2, 6, 5], 0) }

  let(:source_file) do
    instance_double(
      SimpleCov::SourceFile,
      filename: filename, lines: lines,
      covered_lines: lines.values_at(1, 2), missed_lines: [lines.fetch(4)],
      never_lines: lines.values_at(0, 5),
      branches: [inline_branch, block_branch],
      covered_branches: [inline_branch], missed_branches: [block_branch],
      total_branches: [inline_branch, block_branch],
      methods: [covered_method, missed_method],
      covered_methods: [covered_method], missed_methods: [missed_method]
    )
  end

  before do
    # Off by default so each example turns on exactly the criteria it
    # asserts and the sections cannot bleed into one another.
    allow(SimpleCov).to receive_messages(line_coverage?: false, branch_coverage?: false, method_coverage?: false)
  end

  it "carries the source with each line's trailing newline stripped" do
    expect(described_class.call(source_file)).to eq(
      source: ["# a comment", "def bar", "  x = 1 if y", "  hidden", "def baz", "end"]
    )
  end

  it "omits the source when include_source is false" do
    expect(described_class.call(source_file, include_source: false)).to eq({})
  end

  it "carries the line section and its totals" do
    allow(SimpleCov).to receive(:line_coverage?).and_return(true)
    allow(source_file).to receive(:covered_percent).with(no_args).and_return(66.67)

    expect(described_class.call(source_file, include_source: false)).to eq(
      # A skipped line reports as "ignored", and a never line as null.
      lines: [nil, 2, 2, "ignored", 0, nil],
      lines_covered_percent: 66.67,
      covered_lines: 2, missed_lines: 1, omitted_lines: 2, total_lines: 3
    )
  end

  it "carries the branch section and its totals" do
    allow(SimpleCov).to receive(:branch_coverage?).and_return(true)
    allow(source_file).to receive(:covered_percent).with(:branch).and_return(50.0)

    expect(described_class.call(source_file, include_source: false)).to eq(
      branches: [
        # An inline branch reports on its own first line, a block one on
        # the line above, where the condition is written.
        {type: :then, start_line: 3, end_line: 3, coverage: 2, inline: true, report_line: 3},
        {type: :else, start_line: 5, end_line: 6, coverage: 0, inline: false, report_line: 4}
      ],
      branches_covered_percent: 50.0,
      covered_branches: 1, missed_branches: 1, total_branches: 2
    )
  end

  it "carries the method section and its totals" do
    allow(SimpleCov).to receive(:method_coverage?).and_return(true)
    allow(source_file).to receive(:covered_percent).with(:method).and_return(50.0)

    expect(described_class.call(source_file, include_source: false)).to eq(
      # The name is the method's own spelling, a String rather than the
      # Method object JSON would have called `to_s` on regardless.
      methods: [
        {name: "Foo#bar", start_line: 2, end_line: 3, coverage: 2},
        {name: "Foo#baz", start_line: 5, end_line: 6, coverage: 0}
      ],
      methods_covered_percent: 50.0,
      covered_methods: 1, missed_methods: 1, total_methods: 2
    )
  end

  it "carries every enabled criterion's section at once" do
    allow(SimpleCov).to receive_messages(line_coverage?: true, branch_coverage?: true, method_coverage?: true)
    allow(source_file).to receive(:covered_percent).with(no_args).and_return(66.67)
    allow(source_file).to receive(:covered_percent).with(:branch).and_return(50.0)
    allow(source_file).to receive(:covered_percent).with(:method).and_return(50.0)

    expect(described_class.call(source_file).keys).to eq(
      %i[source lines lines_covered_percent covered_lines missed_lines omitted_lines total_lines
         branches branches_covered_percent covered_branches missed_branches total_branches
         methods methods_covered_percent covered_methods missed_methods total_methods]
    )
  end

  it "carries the file's bitmaps in the map's own wire encoding" do
    contexts = SimpleCov::ContextMap.new
    contexts.record("first test", {filename => 0b0110})
    contexts.record("second test", {filename => 0b1000})

    expect(described_class.call(source_file, include_source: false, contexts: contexts))
      .to eq(contexts: {"0" => "6", "1" => "8"})
  end

  # Under a document-level `contexts` array, absence already says "no
  # recorded context executed this file", so an untouched file spends no
  # bytes saying it.
  it "omits the contexts key for a file no recorded context touched" do
    contexts = SimpleCov::ContextMap.new
    contexts.record("first test", {"/project/lib/other.rb" => 0b1})

    expect(described_class.call(source_file, include_source: false, contexts: contexts)).to eq({})
  end

  it "omits the contexts key when no map was recorded" do
    expect(described_class.call(source_file, include_source: false, contexts: nil)).to eq({})
  end

  def line(src, number, coverage, skipped: false)
    line = SimpleCov::SourceFile::Line.new(src, number, coverage)
    line.skipped! if skipped
    line
  end
end
