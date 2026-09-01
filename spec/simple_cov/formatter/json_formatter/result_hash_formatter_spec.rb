# frozen_string_literal: true

require "helper"
require "open3"

RSpec.describe SimpleCov::Formatter::JSONFormatter::ResultHashFormatter,
  mutant_expression: "SimpleCov::Formatter::JSONFormatter*" do
  subject(:document) { described_class.format(result) }

  let(:commit) { "1234567890abcdef1234567890abcdef12345678" }
  let(:fixed_time) { Time.utc(2024, 1, 2, 3, 4, 5, 678_900) }
  let(:sample_path) { source_fixture("json/sample.rb") }
  let(:project_filename) { SimpleCov::SourceFile.new(sample_path, []).project_filename }
  let(:coverage_data) { {sample_path => {"lines" => [nil, 1, 1, 0, nil]}} }

  let(:result) do
    res = SimpleCov::Result.new(coverage_data)
    res.created_at = fixed_time
    res
  end

  let(:line_statistics) do
    {covered: 2, missed: 1, omitted: 17, total: 3, percent: 200 / 3.0, strength: 2 / 3.0}
  end
  let(:expected_meta) do
    {
      schema_version: described_class.const_get(:SCHEMA_VERSION),
      simplecov_version: SimpleCov::VERSION,
      command_name: result.command_name,
      command_names: [result.command_name],
      project_name: SimpleCov.project_name,
      timestamp: "2024-01-02T03:04:05.678Z",
      root: SimpleCov.root,
      commit: commit,
      primary_coverage: "line",
      line_coverage: true, branch_coverage: false, method_coverage: false
    }
  end
  let(:contextual_document) do
    map = SimpleCov::ContextMap.new
    map.record("a test", {sample_path => 0b0110})
    described_class.format(result_with_contexts(map))
  end

  before do
    allow(Open3).to receive(:capture2e)
      .with("git", "-C", SimpleCov.root, "rev-parse", "HEAD")
      .and_return(["#{commit}\n", instance_double(Process::Status, success?: true)])
    allow(SimpleCov::History).to receive(:entries_with).and_return([{"created_at" => "2024-01-01T00:00:00Z"}])
    allow(SimpleCov::Formatter::JSONFormatter::ProductionSectionFormatter).to receive(:call).and_return(nil)
  end

  it "carries the schema pointer" do
    expect(document.fetch(:$schema))
      .to eq("https://raw.githubusercontent.com/simplecov-ruby/simplecov/main/schemas/" \
             "coverage-v#{described_class.const_get(:SCHEMA_VERSION)}.schema.json")
  end

  it "carries the sections a report always has" do
    expect(document.keys).to eq(%i[$schema meta total coverage groups errors])
  end

  it "describes the run in meta" do
    expect(document.fetch(:meta)).to eq(expected_meta)
  end

  it "records which criteria the run measured" do
    allow(SimpleCov).to receive_messages(line_coverage?: false, branch_coverage?: true, method_coverage?: true)

    expect(document.fetch(:meta)).to include(
      line_coverage: false, branch_coverage: true, method_coverage: true
    )
  end

  it "records the commit with the whitespace around it trimmed" do
    allow(Open3).to receive(:capture2e)
      .with("git", "-C", SimpleCov.root, "rev-parse", "HEAD")
      .and_return([" #{commit} \n", instance_double(Process::Status, success?: true)])

    expect(document.fetch(:meta).fetch(:commit)).to eq(commit)
  end

  it "records no commit when the project is not a git checkout" do
    allow(Open3).to receive(:capture2e)
      .with("git", "-C", SimpleCov.root, "rev-parse", "HEAD")
      .and_return(["fatal: not a git repository", instance_double(Process::Status, success?: false)])

    expect(document.fetch(:meta).fetch(:commit)).to be_nil
  end

  it "records no commit when git is not on PATH" do
    allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT)

    expect(document.fetch(:meta).fetch(:commit)).to be_nil
  end

  it "totals only the criteria the run measured" do
    expect(document.fetch(:total)).to eq(lines: line_statistics)
  end

  it "totals a criterion switched on in place of lines" do
    allow(SimpleCov).to receive_messages(line_coverage?: false, branch_coverage?: true)

    expect(document.fetch(:total)).to eq(
      branches: {covered: 0, missed: 0, total: 0, percent: 100.0, strength: 0.0}
    )
  end

  it "keys the per-file coverage on the project-relative path" do
    expect(document.fetch(:coverage).keys).to eq([project_filename])
  end

  it "embeds the source by default" do
    expect(document.fetch(:coverage).fetch(project_filename)).to have_key(:source)
  end

  it "omits the source on request" do
    expect(described_class.format(result, include_source: false).fetch(:coverage).fetch(project_filename))
      .not_to have_key(:source)
  end

  it "names each group's files by their project-relative paths" do
    allow(result).to receive(:groups).and_return("Models" => SimpleCov::FileList.new(result.files.to_a))

    expect(document.fetch(:groups)).to eq(
      "Models" => {lines: line_statistics, files: [project_filename]}
    )
  end

  it "carries the threshold violations the run tripped" do
    allow(SimpleCov).to receive(:minimum_coverage).and_return(line: 95)

    expect(document.fetch(:errors)).to eq(minimum_coverage: {lines: {expected: 95, actual: 66.66}})
  end

  it "omits contexts, history and production when the run carries none" do
    expect(document.keys).not_to include(:contexts, :history, :production)
  end

  it "carries the recorded context list" do
    expect(contextual_document.fetch(:contexts)).to eq(["a test"])
  end

  it "carries each file's bitmaps" do
    expect(contextual_document.fetch(:coverage).fetch(project_filename)).to include(contexts: {"0" => "6"})
  end

  it "carries an empty context list for a run that recorded nothing" do
    expect(described_class.format(result_with_contexts(SimpleCov::ContextMap.new)).fetch(:contexts)).to eq([])
  end

  it "carries the history once there is more than one run to draw" do
    entries = [{"created_at" => "2024-01-01T00:00:00Z"}, {"created_at" => "2024-01-02T00:00:00Z"}]
    allow(SimpleCov::History).to receive(:entries_with).and_return(entries)

    expect(document.fetch(:history)).to eq(entries)
  end

  it "carries the production section when a store answered" do
    section = {files: {"lib/a.rb" => {lines: [1]}}}
    allow(SimpleCov::Formatter::JSONFormatter::ProductionSectionFormatter).to receive(:call).and_return(section)

    expect(document.fetch(:production)).to eq(section)
  end

  def result_with_contexts(map)
    res = SimpleCov::Result.new(coverage_data, contexts: map)
    res.created_at = fixed_time
    res
  end
end
