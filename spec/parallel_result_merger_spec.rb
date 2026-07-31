# frozen_string_literal: true

require "helper"
require "tmpdir"

RSpec.describe SimpleCov::ParallelResultMerger do
  let(:resultset_dir) { Dir.mktmpdir("simplecov-parallel-merge") }

  # `sample.rb` is executed by every shard and the second file by exactly one,
  # so the merged table exercises both summing and union. Every file has to
  # exist on disk: these resultsets get built into real `SimpleCov::Result`s,
  # which warn about coverage for files that have since been removed.
  let(:shards) do
    [
      ["resultset1.rb", {"lines" => [nil, 1, 1, nil]}],
      ["resultset2.rb", {"lines" => [nil, 1, nil, 2]}],
      ["three.rb", {"lines" => [nil, 0, 1, nil]}],
      ["never.rb", {"lines" => [1, nil, nil, nil]}],
      ["inline.rb", {"lines" => [nil, 2, nil, nil]}]
    ]
  end

  let(:paths) do
    shards.each_with_index.map do |(fixture, lines), index|
      write_resultset(
        "shard#{index}",
        {
          source_fixture("sample.rb") => lines,
          source_fixture(fixture) => {"lines" => [index, nil]}
        }
      )
    end
  end

  let(:serial) { SimpleCov::ResultMerger.merge_resultsets(paths, ignore_timeout: true) }

  after { FileUtils.remove_entry(resultset_dir) }

  describe ".merge_and_store" do
    before { FileUtils.mkdir_p(File.dirname(SimpleCov::ResultMerger.resultset_path)) }

    after { FileUtils.rm_f(SimpleCov::ResultMerger.resultset_path) }

    it "produces the result ResultMerger.merge_and_store produces" do
      result = described_class.merge_and_store(*paths, processes: 3, ignore_timeout: true)

      expect(result.original_result)
        .to eq(SimpleCov::ResultMerger.merge_results(*paths, ignore_timeout: true).original_result)
    end

    it "has the result stored" do
      described_class.merge_and_store(*paths, processes: 3, ignore_timeout: true)

      expect(SimpleCov::ResultMerger.read_resultset.keys).to eq([serial.first.sort.join(", ")])
    end

    # The workers do the dropping, so the "older than merge_timeout" warning
    # comes from them and reaches the inherited stderr rather than anything
    # this process can capture.
    it "stores nothing when every resultset is outdated" do
      allow(SimpleCov::ResultMerger).to receive(:store_result)
      stale = Array.new(3) do |index|
        write_resultset("old#{index}", {source_fixture("sample.rb") => {"lines" => [1]}}, outdated: true)
      end

      expect(described_class.merge_and_store(*stale, processes: 2)).to be_nil
      expect(SimpleCov::ResultMerger).not_to have_received(:store_result)
    end
  end

  describe ".merge_results" do
    it "produces the result ResultMerger.merge_results produces" do
      result = described_class.merge_results(*paths, processes: 3, ignore_timeout: true)

      expect(result.original_result)
        .to eq(SimpleCov::ResultMerger.merge_results(*paths, ignore_timeout: true).original_result)
    end

    it "merges in this process when the fan-out cannot run" do
      allow(described_class).to receive(:fork_supported?).and_return(false)

      result = described_class.merge_results(*paths, processes: 3, ignore_timeout: true)

      expect(result.original_result)
        .to eq(SimpleCov::ResultMerger.merge_results(*paths, ignore_timeout: true).original_result)
    end
  end

  describe ".merge_resultsets" do
    it "produces the pair ResultMerger.merge_resultsets produces" do
      expect(described_class.merge_resultsets(paths, processes: 3, ignore_timeout: true)).to eq(serial)
    end

    it "produces the same pair however many processes it is given" do
      merges = [2, 3, 4, 5, 12].map do |processes|
        described_class.merge_resultsets(paths, processes: processes, ignore_timeout: true)
      end

      expect(merges.uniq.size).to eq(1)
    end

    it "honours ignore_timeout: false by dropping expired resultsets" do
      expired = write_resultset("stale", {source_fixture("sample.rb") => {"lines" => [9, 9, 9, 9]}}, outdated: true)
      fresh = paths.first(2)

      command_names, = described_class.merge_resultsets([*fresh, expired], processes: 3, ignore_timeout: false)

      expect(command_names).to contain_exactly("shard0", "shard1", "")
    end

    it "returns nil when a single process was requested" do
      expect(described_class.merge_resultsets(paths, processes: 1)).to be_nil
    end

    it "returns nil when there is only one resultset to merge" do
      expect(described_class.merge_resultsets(paths.first(1), processes: 4)).to be_nil
    end

    it "returns nil when the runtime cannot fork" do
      allow(described_class).to receive(:fork_supported?).and_return(false)

      expect(described_class.merge_resultsets(paths, processes: 4)).to be_nil
    end
  end

  describe ".fork_supported?" do
    # False on JRuby, TruffleRuby and Windows, where `fork` is defined but
    # raises; there is no CRuby-side way to reach the false case.
    it { expect(described_class.fork_supported?).to eq(Process.respond_to?(:fork)) }
  end

  describe ".chunk" do
    it "splits into contiguous slices, in order" do
      expect(described_class.chunk(%w[a b c d e f], 3)).to eq([%w[a b], %w[c d], %w[e f]])
    end

    it "gives the remainder to the leading slices so no worker folds twice its share" do
      expect(described_class.chunk(%w[a b c d e f g], 3)).to eq([%w[a b c], %w[d e], %w[f g]])
    end

    it "makes no more slices than there are files" do
      expect(described_class.chunk(%w[a b c], 10)).to eq([%w[a], %w[b], %w[c]])
    end

    it "leaves the caller's list alone" do
      files = %w[a b c d]
      described_class.chunk(files, 2)

      expect(files).to eq(%w[a b c d])
    end
  end

  describe ".run_worker" do
    let(:pipe) { IO.pipe }

    after { pipe.each { |io| io.close unless io.closed? } }

    it "writes the merged pair and reports success" do
      reader, writer = pipe

      expect(described_class.run_worker(paths, writer, ignore_timeout: true)).to eq(0)
      expect(Marshal.load(reader)).to eq(serial) # rubocop:disable Security/MarshalLoad
    end

    it "reports failure and warns when the merged pair cannot be shipped back" do
      _reader, writer = pipe
      writer.close

      output = capture_stderr do
        expect(described_class.run_worker(paths, writer, ignore_timeout: true)).to eq(1)
      end

      expect(output).to include("parallel merge worker failed", "IOError")
    end

    it "stays quiet about a failed worker when print_errors is off" do
      _reader, writer = pipe
      writer.close

      output = capture_stderr do
        with_print_errors(false) { described_class.run_worker(paths, writer, ignore_timeout: true) }
      end

      expect(output).to be_empty
    end
  end

  describe ".fan_out" do
    let(:chunks) { described_class.chunk(paths, 3) }

    it "returns nil and warns when a worker dies without shipping its slice" do
      allow(described_class).to receive(:run_worker).and_return(1)

      output = capture_stderr do
        expect(described_class.fan_out(chunks, ignore_timeout: true)).to be_nil
      end

      expect(output).to include("parallel merge did not complete (3 of 3 workers failed)")
    end

    it "returns nil when the workers could not be spawned at all" do
      allow(described_class).to receive(:spawn_workers).and_return(nil)

      expect(described_class.fan_out(chunks, ignore_timeout: true)).to be_nil
    end

    it "stays quiet about a failed fan-out when print_errors is off" do
      allow(described_class).to receive(:run_worker).and_return(1)

      output = capture_stderr do
        with_print_errors(false) { described_class.fan_out(chunks, ignore_timeout: true) }
      end

      expect(output).to be_empty
    end
  end

  describe ".spawn_workers" do
    it "tears down the workers it did spawn and returns nil when a fork is refused" do
      spawned = []
      allow(described_class).to receive(:spawn_worker).and_wrap_original do |original, *args, **options|
        raise NotImplementedError, "fork is not available on this platform" if spawned.any?

        original.call(*args, **options).tap { |worker| spawned << worker }
      end

      expect(described_class.spawn_workers(described_class.chunk(paths, 3), ignore_timeout: true)).to be_nil
      expect(spawned.first[:reader]).to be_closed
    end
  end

  describe ".read_payload" do
    it "returns nil for a stream a worker never finished writing" do
      reader, writer = IO.pipe
      writer.write(Marshal.dump([["shard0"], {}]).byteslice(0, 4))
      writer.close

      expect(described_class.read_payload(reader)).to be_nil
    ensure
      reader.close
    end
  end

  describe ".succeeded?" do
    it "is false for a pid it cannot reap" do
      expect(described_class.succeeded?(-1)).to be false
    end
  end

private

  def write_resultset(command_name, coverage, outdated: false)
    timestamp = Time.now.to_i - (outdated ? SimpleCov.merge_timeout * 2 : 0)
    path = File.join(resultset_dir, ".resultset-#{command_name}.json")
    File.write(path, JSON.generate(command_name => {"coverage" => coverage, "timestamp" => timestamp}))
    path
  end

  def with_print_errors(value)
    previous = SimpleCov.print_errors
    SimpleCov.print_errors value
    yield
  ensure
    SimpleCov.print_errors previous
  end
end
