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
    context "with meta at the head of the document" do
      before do
        File.write(path, JSON.generate(meta: {timestamp: timestamp, command_name: "RSpec"},
          coverage: {"a.rb" => {"source" => ["x"]}}))
        allow(described_class).to receive(:parse_meta_full)
      end

      it "reads timestamp and command_name" do
        expect(described_class.existing_meta(path))
          .to match(hash_including(timestamp: Time.iso8601(timestamp), command_name: "RSpec"))
      end

      it "never falls back to a full parse" do
        described_class.existing_meta(path)

        expect(described_class).not_to have_received(:parse_meta_full)
      end
    end

    it "falls back to a full parse when a meta string contains a brace" do
      File.write(path, JSON.generate(meta: {timestamp: timestamp, command_name: "Weird } Name"}))

      expect(described_class.existing_meta(path)[:command_name]).to eq("Weird } Name")
    end

    context "when meta sits beyond the scanned head" do
      before do
        File.write(path, JSON.generate(coverage: {"a.rb" => {"source" => ["x" * 70_000]}},
          meta: {timestamp: timestamp, command_name: "RSpec"}))
        allow(described_class).to receive(:parse_meta_full).and_call_original
      end

      it "reads the command name" do
        expect(described_class.existing_meta(path)[:command_name]).to eq("RSpec")
      end

      it "falls back to a full parse" do
        described_class.existing_meta(path)

        expect(described_class).to have_received(:parse_meta_full)
      end
    end

    context "with a meta object that spans lines, as this writer emits it" do
      before do
        File.write(path, JSON.pretty_generate(meta: {timestamp: timestamp, command_name: "RSpec"}))
        allow(described_class).to receive(:parse_meta_full).and_call_original
      end

      it "reads the command name" do
        expect(described_class.existing_meta(path)[:command_name]).to eq("RSpec")
      end

      it "never falls back to a full parse" do
        described_class.existing_meta(path)

        expect(described_class).not_to have_received(:parse_meta_full)
      end
    end

    context "with an empty meta object" do
      before do
        File.write(path, JSON.generate(meta: {}, coverage: {}))
        allow(described_class).to receive(:parse_meta_full).and_call_original
      end

      it "reads it out of the head as carrying no metadata" do
        expect(described_class.existing_meta(path)).to be_nil
      end

      it "never falls back to a full parse" do
        described_class.existing_meta(path)

        expect(described_class).not_to have_received(:parse_meta_full)
      end
    end

    it "reads a document that carries no meta at all as carrying none" do
      File.write(path, JSON.generate(coverage: {}))

      expect(described_class.existing_meta(path)).to be_nil
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

    it "reads an epoch integer timestamp the way a foreign formatter writes it" do
      moment = Time.at(Time.now.to_i)
      File.write(path, JSON.generate(meta: {timestamp: moment.to_i, command_name: "RSpec"}))

      expect(described_class.existing_meta(path)[:timestamp]).to eq(moment)
    end

    it "returns nil for a timestamp that is neither a string nor a number" do
      File.write(path, JSON.generate(meta: {timestamp: true}))
      expect(described_class.existing_meta(path)).to be_nil
    end
  end

  it "reads an empty file as carrying no metadata" do
    File.write(path, "")

    expect(described_class.existing_meta(path)).to be_nil
  end

  it "reads metadata with no timestamp at all as carrying none" do
    File.write(path, JSON.generate(meta: {command_name: "RSpec"}))

    expect(described_class.existing_meta(path)).to be_nil
  end

  it "reads a document that parses to a Hash subclass" do
    allow(described_class).to receive(:parse_meta_head).and_return(nil)
    allow(JSON).to receive(:parse).and_return(Class.new(Hash).new.merge!(meta: {timestamp: timestamp}))
    File.write(path, "{}")

    expect(described_class.existing_meta(path)[:timestamp]).to be_within(1).of(Time.now)
  end

  it "reads a document that parses to something other than a Hash as carrying none" do
    File.write(path, "[]")

    expect(described_class.existing_meta(path)).to be_nil
  end

  describe ".write" do
    let(:result) { instance_double(SimpleCov::Result, command_name: "RSpec") }

    around { |example| Dir.chdir(tmp) { example.run } }

    context "when writing a document" do
      let(:written) { described_class.write(tmp, {"meta" => {"command_name" => "RSpec"}}, result) }

      it "answers the path of the fixed filename" do
        expect(written).to eq(path)
      end

      it "writes the document as pretty JSON" do
        written

        expect(File.read(path)).to eq(%({\n  "meta": {\n    "command_name": "RSpec"\n  }\n}))
      end
    end

    context "when writing bytes, not text" do
      before do
        allow(SimpleCov::AtomicFile).to receive(:write).and_call_original
        described_class.write(tmp, {"a" => "b"}, result)
      end

      it "lands the document on disk" do
        expect(File.binread(path)).to eq(%({\n  "a": "b"\n}))
      end

      it "asks for a binary write" do
        expect(SimpleCov::AtomicFile).to have_received(:write).with(path, anything, binary: true)
      end
    end

    context "when checking for a concurrent writer" do
      let(:existed_at_check) { [] }

      before do
        allow(described_class).to receive(:warn_if_concurrent_overwrite) { existed_at_check << File.exist?(path) }
        described_class.write(tmp, {"a" => "b"}, result)
      end

      it "checks before overwriting, not after" do
        expect(existed_at_check).to eq([false])
      end

      it "names the path and the result" do
        expect(described_class).to have_received(:warn_if_concurrent_overwrite).with(path, result)
      end
    end
  end

  describe ".warn_if_concurrent_overwrite" do
    let(:started) { Time.now }
    let(:result) { instance_double(SimpleCov::Result, command_name: "RSpec") }
    let(:concurrent_warning) do
      "simplecov: #{path} was written at #{(started + 5).iso8601} — after " \
      "this process started at #{started.iso8601}. Overwriting " \
      "likely loses coverage data from a concurrent test run. For " \
      "parallel test setups, use SimpleCov::ResultMerger or run a single " \
      "collation step after all workers finish.\n"
    end

    before { allow(SimpleCov).to receive(:process_start_time).and_return(started) }

    def write_existing(written_at, command_name: "Minitest")
      File.write(path, JSON.generate(meta: {timestamp: written_at.iso8601(3), command_name: command_name}))
    end

    def warning
      capture_stderr { described_class.warn_if_concurrent_overwrite(path, result) }
    end

    it "warns, naming both times and what to do instead" do
      write_existing(started + 5)

      expect(warning).to eq(concurrent_warning)
    end

    it "says nothing about a file written before this process started" do
      write_existing(started - 5)

      expect(warning).to be_empty
    end

    it "says nothing about a file written at the very moment we started" do
      write_existing(started)

      expect(warning).to be_empty
    end

    it "says nothing about our own run's file" do
      write_existing(started + 5, command_name: "RSpec")

      expect(warning).to be_empty
    end

    it "says nothing when there is no file to overwrite" do
      expect(warning).to be_empty
    end

    it "says nothing when the existing file carries no usable timestamp" do
      File.write(path, JSON.generate(meta: {timestamp: "not a time", command_name: "Minitest"}))

      expect(warning).to be_empty
    end

    it "says nothing when this process has no recorded start time" do
      allow(SimpleCov).to receive(:process_start_time).and_return(nil)
      write_existing(Time.now + 5)

      expect(warning).to be_empty
    end
  end
end
