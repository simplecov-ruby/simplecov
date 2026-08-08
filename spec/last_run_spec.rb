# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::LastRun do
  subject(:last_run) { described_class }

  it "defines a last_run_path" do
    expect(last_run.last_run_path).to include "tmp/coverage/.last_run.json"
  end

  it "writes json to its last_run_path that can be parsed again" do
    structure = [{"key" => "value"}]
    last_run.write(structure)
    file_contents = File.read(last_run.last_run_path)
    expect(JSON.parse(file_contents)).to eq structure
    expect(file_contents).to end_with("\n")
  end

  context "when reading" do
    # Don't leak this describe's fixtures (the corrupt ones especially)
    # into later examples: anything formatting a result reads
    # .last_run.json through the maximum_coverage_drop check.
    after { FileUtils.rm_f(last_run.last_run_path) }

    context "when the last_run file does not exist" do
      before { FileUtils.rm_f(last_run.last_run_path) }

      it "returns nil" do
        expect(last_run.read).to be_nil
      end
    end

    context "when a non empty result" do
      before { last_run.write("result" => {"covered_percent" => 100.0}) }

      it "reads json from its last_run_path with symbolized keys" do
        expect(last_run.read).to eq(result: {covered_percent: 100.0})
      end
    end

    context "when the file holds corrupt JSON" do
      before { File.write(last_run.last_run_path, "{\"result\":") }

      it "warns and returns nil instead of raising" do
        expect { expect(last_run.read).to be_nil }
          .to output(/Parsing JSON content of \.last_run\.json failed/).to_stderr
      end
    end

    context "when the file holds valid JSON that is not an object" do
      before { File.write(last_run.last_run_path, "[1, 2]") }

      it "warns and returns nil so the drop check treats it as no previous run" do
        expect { expect(last_run.read).to be_nil }
          .to output(/Parsing JSON content of \.last_run\.json failed/).to_stderr
      end
    end

    context "when an empty result" do
      before do
        File.open(last_run.last_run_path, "w+") do |f|
          f.puts ""
        end
      end

      it "returns nil" do
        expect(last_run.read).to be_nil
      end
    end
  end
end
