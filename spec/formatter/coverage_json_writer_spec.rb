# frozen_string_literal: true

require "helper"
require "json"
require "tmpdir"

RSpec.describe SimpleCov::Formatter::CoverageJSONWriter do
  let(:tmp) { Dir.mktmpdir("simplecov-coverage-json-writer-spec-") }
  let(:path) { File.join(tmp, "coverage.json") }
  let(:timestamp) { Time.now.iso8601(3) }

  after { FileUtils.rm_rf(tmp) }

  describe ".existing_meta" do
    it "reads timestamp and command_name from the head without a full parse" do
      File.write(path, JSON.generate(meta: {timestamp: timestamp, command_name: "RSpec"},
                                     coverage: {"a.rb" => {"source" => ["x"]}}))
      allow(described_class).to receive(:parse_meta_full)

      meta = described_class.existing_meta(path)

      expect(meta[:timestamp]).to eq(Time.iso8601(timestamp))
      expect(meta[:command_name]).to eq("RSpec")
      expect(described_class).not_to have_received(:parse_meta_full)
    end

    it "falls back to a full parse when a meta string contains a brace" do
      File.write(path, JSON.generate(meta: {timestamp: timestamp, command_name: "Weird } Name"}))

      expect(described_class.existing_meta(path)[:command_name]).to eq("Weird } Name")
    end

    it "falls back to a full parse when meta sits beyond the scanned head" do
      File.write(path, JSON.generate(coverage: {"a.rb" => {"source" => ["x" * 70_000]}},
                                     meta: {timestamp: timestamp, command_name: "RSpec"}))

      expect(described_class.existing_meta(path)[:command_name]).to eq("RSpec")
    end

    it "returns nil when the file is missing" do
      expect(described_class.existing_meta(path)).to be_nil
    end

    it "returns nil when the file is not a JSON object" do
      File.write(path, "[1, 2]")
      expect(described_class.existing_meta(path)).to be_nil
    end

    it "returns nil when the timestamp is unparseable" do
      File.write(path, JSON.generate(meta: {timestamp: "not a time"}))
      expect(described_class.existing_meta(path)).to be_nil
    end
  end
end
