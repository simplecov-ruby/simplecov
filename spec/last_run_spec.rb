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
  end

  context "when reading" do
    context "when the last_run file does not exist" do
      before { FileUtils.rm_f(last_run.last_run_path) }

      it "returns nil" do
        expect(last_run.read).to be_nil
      end
    end

    context "when a non empty result" do
      before { last_run.write([]) }

      it "reads json from its last_run_path" do
        expect(last_run.read).to eq([])
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
