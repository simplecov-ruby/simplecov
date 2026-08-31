# frozen_string_literal: true

require "helper"
require "tmpdir"

RSpec.describe SimpleCov::Formatter::BaselineFormatter do
  subject(:formatter) { described_class.new }

  let(:tmp) { Dir.mktmpdir("simplecov-baseline-formatter-spec-") }
  let(:baseline_path) { File.join(tmp, ".simplecov_baseline.yml") }

  let(:result) do
    SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}})
  end
  let(:project_filename) { SimpleCov::SourceFile.new(source_fixture("json/sample.rb"), []).project_filename }

  before { allow(SimpleCov).to receive(:baseline_file).and_return(baseline_path) }

  after { FileUtils.remove_entry(tmp) }

  def read_baseline
    SimpleCov::Baseline.read_if_exists(baseline_path)
  end

  def format_result
    capture_stderr { formatter.format(result) }
  end

  context "with no baseline file yet" do
    it "generates a floor for every reported file" do
      output = format_result

      expect(read_baseline.floor_for(project_filename, :line)).to have_attributes(percent: 66.66, missed: 1)
      expect(output).to eq("Coverage baseline generated to #{baseline_path} (1 file)\n")
    end

    it "pluralizes the generation summary" do
      result = SimpleCov::Result.new(
        {
          source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]},
          source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}
        }
      )

      output = capture_stderr { formatter.format(result) }

      expect(output).to eq("Coverage baseline generated to #{baseline_path} (2 files)\n")
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
      expect(output).to eq("Coverage baseline ratcheted to #{baseline_path} (1 tightened, 0 pruned)\n")
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
      expect(output).to eq(
        "Coverage baseline unchanged at #{baseline_path}, 1 file below its floor: #{project_filename}\n"
      )
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
      expect(output).to eq("Coverage baseline unchanged at #{baseline_path}\n")
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

      expect(output).to eq(
        "Coverage baseline unchanged at #{baseline_path}, " \
        "2 files below their floors: #{project_filename}, #{sibling_filename}\n"
      )
    end
  end

  context "with a baseline that does not cover the reported file" do
    before do
      File.write(baseline_path, "lib/covered_elsewhere.rb: 41.2\n")
    end

    it "adds no entry, and prunes the file the report no longer carries" do
      output = format_result

      expect(read_baseline.entries).to be_empty
      expect(output).to eq("Coverage baseline ratcheted to #{baseline_path} (0 tightened, 1 pruned)\n")
    end
  end

  it "writes a relative baseline_file under SimpleCov.root, not the working directory" do
    Dir.mktmpdir("simplecov-baseline-root-") do |root|
      Dir.mktmpdir("simplecov-baseline-cwd-") do |elsewhere|
        allow(SimpleCov).to receive_messages(root: root, baseline_file: ".simplecov_baseline.yml")

        Dir.chdir(elsewhere) { format_result }

        expect(File).to exist(File.join(root, ".simplecov_baseline.yml"))
        expect(File).not_to exist(File.join(elsewhere, ".simplecov_baseline.yml"))
      end
    end
  end

  it "writes floors only for the criteria the run measured" do
    allow(SimpleCov).to receive(:branch_coverage?).and_return(false)
    format_result

    expect(read_baseline.covers?(project_filename, :line)).to be true
    expect(read_baseline.covers?(project_filename, :branch)).to be false
  end

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
