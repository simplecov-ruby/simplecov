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
  let(:formatted) { capture_stderr { formatter.format(result) } }

  before { allow(SimpleCov).to receive(:baseline_file).and_return(baseline_path) }

  after { FileUtils.remove_entry(tmp) }

  def read_baseline
    SimpleCov::Baseline.read_if_exists(baseline_path)
  end

  context "with no baseline file yet" do
    it "generates a floor for every reported file" do
      formatted

      expect(read_baseline.floor_for(project_filename, :line)).to have_attributes(percent: 66.66, missed: 1)
    end

    it "names the file it generated" do
      expect(formatted).to eq("Coverage baseline generated to #{baseline_path} (1 file)\n")
    end

    context "with more than one file in the report" do
      let(:result) do
        SimpleCov::Result.new(
          {
            source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]},
            source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}
          }
        )
      end

      it "pluralizes the generation summary" do
        expect(formatted).to eq("Coverage baseline generated to #{baseline_path} (2 files)\n")
      end
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

    it "ratchets the floor up" do
      formatted

      expect(read_baseline.floor_for(project_filename, :line)).to have_attributes(percent: 66.66, missed: 1)
    end

    it "says so" do
      expect(formatted).to eq("Coverage baseline ratcheted to #{baseline_path} (1 tightened, 0 pruned)\n")
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

    it "keeps the floor, leaving the file untouched" do
      before_content = File.read(baseline_path)
      formatted

      expect(File.read(baseline_path)).to eq(before_content)
    end

    it "names the regression" do
      expect(formatted).to eq(
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

    it "leaves the file unrewritten" do
      before_content = File.read(baseline_path)
      formatted

      expect(File.read(baseline_path)).to eq(before_content)
    end

    it "reports it unchanged" do
      expect(formatted).to eq("Coverage baseline unchanged at #{baseline_path}\n")
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
      expect(formatted).to eq(
        "Coverage baseline unchanged at #{baseline_path}, " \
        "2 files below their floors: #{project_filename}, #{sibling_filename}\n"
      )
    end
  end

  context "with a baseline that does not cover the reported file" do
    before do
      File.write(baseline_path, "lib/covered_elsewhere.rb: 41.2\n")
    end

    it "adds no entry" do
      formatted

      expect(read_baseline.entries).to be_empty
    end

    it "prunes the file the report no longer carries" do
      expect(formatted).to eq("Coverage baseline ratcheted to #{baseline_path} (0 tightened, 1 pruned)\n")
    end
  end

  context "with a relative baseline_file" do
    let(:root) { Dir.mktmpdir("simplecov-baseline-root-") }
    let(:elsewhere) { Dir.mktmpdir("simplecov-baseline-cwd-") }

    before do
      allow(SimpleCov).to receive_messages(root: root, baseline_file: ".simplecov_baseline.yml")
      Dir.chdir(elsewhere) { formatted }
    end

    after do
      FileUtils.remove_entry(root)
      FileUtils.remove_entry(elsewhere)
    end

    it "writes it under SimpleCov.root" do
      expect(File).to exist(File.join(root, ".simplecov_baseline.yml"))
    end

    it "writes nothing in the working directory" do
      expect(File).not_to exist(File.join(elsewhere, ".simplecov_baseline.yml"))
    end
  end

  context "when the run measured line coverage alone" do
    before do
      allow(SimpleCov).to receive(:branch_coverage?).and_return(false)
      formatted
    end

    it "writes a line floor" do
      expect(read_baseline.covers?(project_filename, :line)).to be true
    end

    it "writes no branch floor" do
      expect(read_baseline.covers?(project_filename, :branch)).to be false
    end
  end

  context "when the configuration turns line coverage off and method coverage on" do
    before do
      allow(SimpleCov).to receive_messages(line_coverage?: false, method_coverage?: true)
      formatted
    end

    it "writes no line floor" do
      expect(read_baseline.covers?(project_filename, :line)).to be false
    end

    it "writes a method floor" do
      expect(read_baseline.covers?(project_filename, :method)).to be true
    end
  end

  context "when branch coverage is enabled" do
    let(:result) do
      SimpleCov::Result.new({
        source_fixture("json/sample.rb") => {
          "lines" => [1, 0, 1],
          "branches" => {[:if, 0, 1, 0, 3, 0] => {
            [:then, 1, 2, 2, 2, 6] => 1,
            [:else, 2, 3, 2, 3, 6] => 0
          }}
        }
      })
    end

    before do
      allow(SimpleCov).to receive(:branch_coverage?).and_return(true)
      formatted
    end

    it "includes branch floors" do
      expect(read_baseline.floor_for(project_filename, :branch)).to have_attributes(percent: 50.0, missed: 1)
    end
  end

  context "with silent: true" do
    let(:formatted) { capture_stderr { described_class.new(silent: true).format(result) } }

    it "stays quiet" do
      expect(formatted).to be_empty
    end

    it "still writes the baseline" do
      formatted

      expect(read_baseline).not_to be_nil
    end
  end
end
