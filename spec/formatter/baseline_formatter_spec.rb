# frozen_string_literal: true

require "helper"
require "tmpdir"

RSpec.describe SimpleCov::Formatter::BaselineFormatter do
  subject(:formatter) { described_class.new }

  let(:tmp) { Dir.mktmpdir("simplecov-baseline-formatter-spec-") }
  let(:baseline_path) { File.join(tmp, ".simplecov_baseline.yml") }

  # 2 covered, 1 missed: 66.66% with 1 missed line.
  let(:result) do
    SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}})
  end
  let(:project_filename) { SimpleCov::SourceFile.new(source_fixture("json/sample.rb"), []).project_filename }

  before { allow(SimpleCov).to receive(:baseline_file).and_return(baseline_path) }

  after { FileUtils.remove_entry(tmp) }

  def read_baseline
    SimpleCov::Baseline.read(baseline_path)
  end

  def format_result
    capture_stderr { formatter.format(result) }
  end

  context "with no baseline file yet" do
    it "generates a floor for every reported file" do
      output = format_result

      expect(read_baseline.floor_for(project_filename, :line)).to have_attributes(percent: 66.66, missed: 1)
      expect(output).to include("Coverage baseline generated")
      expect(output).to include("1 file")
    end

    it "pluralizes the generation summary" do
      result = SimpleCov::Result.new(
        {
          source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]},
          source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}
        }
      )

      output = capture_stderr { formatter.format(result) }

      expect(output).to include("2 files")
    end
  end

  context "with an existing baseline the run improved on" do
    before do
      File.write(baseline_path, <<~YAML)
        #{project_filename}:
          lines:
            percent: 50.0
            missed: 2
      YAML
    end

    it "ratchets the floor up and says so" do
      output = format_result

      expect(read_baseline.floor_for(project_filename, :line)).to have_attributes(percent: 66.66, missed: 1)
      expect(output).to include("Coverage baseline ratcheted")
      expect(output).to include("1 tightened")
    end
  end

  context "with a baseline the run fell below" do
    before do
      File.write(baseline_path, <<~YAML)
        #{project_filename}:
          lines:
            percent: 100.0
            missed: 0
      YAML
    end

    it "keeps the floor, leaves the file untouched, and names the regression" do
      before_content = File.read(baseline_path)
      output = format_result

      expect(File.read(baseline_path)).to eq(before_content)
      expect(output).to include("Coverage baseline unchanged")
      expect(output).to include("1 file below its floor")
    end
  end

  context "with a baseline already matching the run" do
    before do
      File.write(baseline_path, <<~YAML)
        #{project_filename}:
          lines:
            percent: 66.66
            missed: 1
      YAML
    end

    it "reports it unchanged without rewriting the file" do
      before_content = File.read(baseline_path)
      output = format_result

      expect(File.read(baseline_path)).to eq(before_content)
      expect(output).to include("Coverage baseline unchanged")
      expect(output).not_to include("below its floor")
    end
  end

  context "with several files below their floors" do
    let(:sibling_filename) { SimpleCov::SourceFile.new(source_fixture("sample.rb"), []).project_filename }
    let(:result) do
      SimpleCov::Result.new(
        {
          source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]},
          source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 0, nil, nil, 1, 1, nil, nil]}
        }
      )
    end

    before do
      File.write(baseline_path, <<~YAML)
        #{project_filename}:
          lines:
            percent: 100.0
            missed: 0
        #{sibling_filename}:
          lines:
            percent: 100.0
            missed: 0
      YAML
    end

    it "pluralizes the below-floors note" do
      output = format_result

      expect(output).to include("2 files below their floors")
    end
  end

  # Auto-ratcheting keeps ratchet semantics: files the baseline never
  # covered stay uncovered, answering to the global standard instead of
  # being grandfathered at whatever they launched with.
  context "with a baseline that does not cover the reported file" do
    before do
      File.write(baseline_path, "lib/covered_elsewhere.rb: 41.2\n")
    end

    it "adds no entry, and prunes the file the report no longer carries" do
      format_result

      baseline = read_baseline
      expect(baseline.entry_for(project_filename)).to be_nil
      expect(baseline.entry_for("lib/covered_elsewhere.rb")).to be_nil
    end
  end

  it "writes floors only for the criteria the run measured" do
    allow(SimpleCov).to receive(:branch_coverage?).and_return(false)
    format_result

    expect(read_baseline.covers?(project_filename, :line)).to be true
    expect(read_baseline.covers?(project_filename, :branch)).to be false
  end

  # A `disable_coverage :line` run under method coverage is a real
  # configuration: only the measured criteria become floors.
  it "follows the configuration for every criterion, line included" do
    allow(SimpleCov).to receive_messages(line_coverage?: false, method_coverage?: true)
    format_result

    baseline = read_baseline
    expect(baseline.covers?(project_filename, :line)).to be false
    expect(baseline.covers?(project_filename, :method)).to be true
  end

  it "includes branch floors when branch coverage is enabled" do
    allow(SimpleCov).to receive(:branch_coverage?).and_return(true)
    result = SimpleCov::Result.new({
                                     source_fixture("json/sample.rb") => {
                                       "lines" => [1, 0, 1],
                                       "branches" => {[:if, 0, 1, 0, 3, 0] => {
                                         [:then, 1, 2, 2, 2, 6] => 1,
                                         [:else, 2, 3, 2, 3, 6] => 0
                                       }}
                                     }
                                   })

    capture_stderr { formatter.format(result) }

    expect(read_baseline.floor_for(project_filename, :branch)).to have_attributes(percent: 50.0, missed: 1)
  end

  it "stays quiet under silent: true" do
    output = capture_stderr { described_class.new(silent: true).format(result) }

    expect(output).to be_empty
    expect(read_baseline).not_to be_nil
  end
end
