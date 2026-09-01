# frozen_string_literal: true

require "helper"
require "tmpdir"

RSpec.describe SimpleCov::ParallelResultMerger do
  let(:resultset_dir) { Dir.mktmpdir("simplecov-parallel-merge") }

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

  let(:serial) { SimpleCov::ResultMerger.absorb_results(paths, ignore_timeout: true) }

  after { FileUtils.remove_entry(resultset_dir) }

  around do |example|
    previous_dir = SimpleCov.coverage_dir
    Dir.mktmpdir("simplecov-parallel-merge-coverage-") do |dir|
      SimpleCov.coverage_dir(dir)
      example.run
    ensure
      SimpleCov.coverage_dir(previous_dir)
    end
  end

  describe ".merge_and_store" do
    it "produces the result ResultMerger.merge_and_store produces" do
      result = described_class.merge_and_store(*paths, processes: 3, ignore_timeout: true)

      expect(result.original_result)
        .to eq(SimpleCov::ResultMerger.merge_results(*paths, ignore_timeout: true).original_result)
    end

    it "has the result stored" do
      described_class.merge_and_store(*paths, processes: 3, ignore_timeout: true)

      expect(SimpleCov::ResultMerger.read_resultset.keys).to eq([serial.first.sort.join(", ")])
    end

    context "with a single process" do
      before { allow(SimpleCov::ResultMerger).to receive(:merge_and_store) }

      it "hands the merge straight to ResultMerger" do
        described_class.merge_and_store(*paths, processes: 1, ignore_timeout: true)

        expect(SimpleCov::ResultMerger).to have_received(:merge_and_store).with(*paths, ignore_timeout: true).once
      end

      it "answers nothing of its own" do
        expect(described_class.merge_and_store(*paths, processes: 1, ignore_timeout: true)).to be_nil
      end
    end

    it "fans out for two processes", if: FORK_SUPPORTED do
      allow(SimpleCov::ResultMerger).to receive(:merge_and_store).and_call_original

      described_class.merge_and_store(*paths, processes: 2, ignore_timeout: true)

      expect(SimpleCov::ResultMerger).not_to have_received(:merge_and_store)
    end

    it "fans out rather than handing back for more than one process", if: FORK_SUPPORTED do
      allow(SimpleCov::ResultMerger).to receive(:merge_and_store).and_call_original

      described_class.merge_and_store(*paths, processes: 3, ignore_timeout: true)

      expect(SimpleCov::ResultMerger).not_to have_received(:merge_and_store)
    end

    it "honours the merge timeout when nothing says to ignore it", if: FORK_SUPPORTED do
      allow(SimpleCov::ResultMerger).to receive(:store_result)
      expired = write_resultset("stale", {source_fixture("sample.rb") => {"lines" => [9]}}, outdated: true)

      described_class.merge_and_store(*paths.first(2), expired, processes: 3)

      expect(SimpleCov::ResultMerger).to have_received(:store_result)
        .with(having_attributes(command_name: "shard0, shard1"))
    end

    it "carries ignore_timeout through to the merge", if: FORK_SUPPORTED do
      allow(SimpleCov::ResultMerger).to receive(:store_result)
      expired = write_resultset("stale", {source_fixture("sample.rb") => {"lines" => [9]}}, outdated: true)

      described_class.merge_and_store(*paths.first(2), expired, processes: 3, ignore_timeout: true)

      expect(SimpleCov::ResultMerger).to have_received(:store_result)
        .with(having_attributes(command_name: "shard0, shard1, stale"))
    end

    context "when every resultset is outdated" do
      let(:stale) do
        Array.new(3) do |index|
          write_resultset("old#{index}", {source_fixture("sample.rb") => {"lines" => [1]}}, outdated: true)
        end
      end

      before { allow(SimpleCov::ResultMerger).to receive(:store_result) }

      it "answers nothing of its own" do
        expect(described_class.merge_and_store(*stale, processes: 2)).to be_nil
      end

      it "stores nothing" do
        described_class.merge_and_store(*stale, processes: 2)

        expect(SimpleCov::ResultMerger).not_to have_received(:store_result)
      end
    end
  end

  describe ".merge_results" do
    it "produces the result ResultMerger.merge_results produces" do
      result = described_class.merge_results(*paths, processes: 3, ignore_timeout: true)

      expect(result.original_result)
        .to eq(SimpleCov::ResultMerger.merge_results(*paths, ignore_timeout: true).original_result)
    end

    it "honours the merge timeout when nothing says to ignore it", if: FORK_SUPPORTED do
      expired = write_resultset("stale", {source_fixture("sample.rb") => {"lines" => [9]}}, outdated: true)

      result = described_class.merge_results(*paths.first(2), expired, processes: 3)

      expect(result.command_name).to eq("shard0, shard1")
    end

    it "carries ignore_timeout through to the workers", if: FORK_SUPPORTED do
      expired = write_resultset("stale", {source_fixture("sample.rb") => {"lines" => [9]}}, outdated: true)

      result = described_class.merge_results(*paths.first(2), expired, processes: 3, ignore_timeout: true)

      expect(result.command_name).to eq("shard0, shard1, stale")
    end

    it "injects the tracked files the workers saw", if: FORK_SUPPORTED do
      unloaded = source_fixture("never.rb")
      tracked = Array.new(3) { |index| write_resultset("t#{index}", {}, tracked_files: [unloaded]) }

      result = described_class.merge_results(*tracked, processes: 3, ignore_timeout: true)

      expect(result.filenames).to include(unloaded)
    end

    it "carries back the test maps the workers saw", if: FORK_SUPPORTED do
      result = described_class.merge_results(*mapped_resultsets, processes: 3, ignore_timeout: true)

      expect(result.contexts.covering(lib_file, 2)).to eq(["spec/w1_spec.rb:1"])
    end

    it "leaves the serial merge alone when the fan-out came back whole", if: FORK_SUPPORTED do
      allow(SimpleCov::ResultMerger).to receive(:merge_results).and_call_original

      described_class.merge_results(*paths, processes: 3, ignore_timeout: true)

      expect(SimpleCov::ResultMerger).not_to have_received(:merge_results)
    end

    it "merges in this process when the fan-out cannot run" do
      without_fork

      result = described_class.merge_results(*paths, processes: 3, ignore_timeout: true)

      expect(result.original_result)
        .to eq(SimpleCov::ResultMerger.merge_results(*paths, ignore_timeout: true).original_result)
    end

    it "carries ignore_timeout into the serial fallback" do
      without_fork
      expired = write_resultset("stale", {source_fixture("sample.rb") => {"lines" => [9]}}, outdated: true)

      result = described_class.merge_results(*paths.first(2), expired, processes: 3, ignore_timeout: true)

      expect(result.command_name).to eq("shard0, shard1, stale")
    end

    it "honours the merge timeout in the serial fallback when nothing ignores it" do
      without_fork
      expired = write_resultset("stale", {source_fixture("sample.rb") => {"lines" => [9]}}, outdated: true)

      result = described_class.merge_results(*paths.first(2), expired, processes: 3)

      expect(result.command_name).to eq("shard0, shard1")
    end
  end

  describe ".absorb_results" do
    it "produces the pair ResultMerger.absorb_results produces", if: FORK_SUPPORTED do
      expect(described_class.absorb_results(paths, processes: 3, ignore_timeout: true)).to eq(serial)
    end

    it "produces the same pair however many processes it is given", if: FORK_SUPPORTED do
      merges = [2, 3, 4, 5, 12].map do |processes|
        described_class.absorb_results(paths, processes: processes, ignore_timeout: true)
      end

      expect(merges).to all(eq(serial))
    end

    it "honours ignore_timeout: false by dropping expired resultsets", if: FORK_SUPPORTED do
      expired = write_resultset("stale", {source_fixture("sample.rb") => {"lines" => [9, 9, 9, 9]}}, outdated: true)
      fresh = paths.first(2)

      command_names, = described_class.absorb_results([*fresh, expired], processes: 3, ignore_timeout: false)

      expect(command_names).to contain_exactly("shard0", "shard1", "")
    end

    it "unions the tracked files every worker saw", if: FORK_SUPPORTED do
      tracked_files = Set.new
      tracked = Array.new(3) { |index| write_resultset("t#{index}", {}, tracked_files: ["tracked#{index}.rb"]) }

      described_class.absorb_results(tracked, processes: 3, ignore_timeout: true, tracked_files: tracked_files)

      expect(tracked_files).to eq(Set["tracked0.rb", "tracked1.rb", "tracked2.rb"])
    end

    context "with test maps from every worker", if: FORK_SUPPORTED do
      let(:context_maps) { SimpleCov::ContextMap::Union.new }
      let(:absorbed_maps) do
        described_class.absorb_results(mapped_resultsets, processes: 3, ignore_timeout: true,
          context_maps: context_maps)
        context_maps.map
      end

      it "unions what each worker recorded" do
        expect(absorbed_maps.covering(lib_file, 2)).to eq(["spec/w1_spec.rb:1"])
      end

      it "keeps one context per worker" do
        expect(absorbed_maps.contexts.size).to eq(3)
      end
    end

    it "honours the merge timeout by default", if: FORK_SUPPORTED do
      expired = write_resultset("stale", {source_fixture("sample.rb") => {"lines" => [9]}}, outdated: true)

      command_names, = described_class.absorb_results([*paths.first(2), expired], processes: 3)

      expect(command_names).to contain_exactly("shard0", "shard1", "")
    end

    it "closes every worker's reader", if: FORK_SUPPORTED do
      readers = []
      record_readers(readers)

      described_class.absorb_results(paths, processes: 3, ignore_timeout: true)

      expect(readers).to have_attributes(size: 3).and all(be_closed)
    end

    it "carries ignore_timeout through to the workers", if: FORK_SUPPORTED do
      expired = write_resultset("stale", {source_fixture("sample.rb") => {"lines" => [9]}}, outdated: true)

      command_names, = described_class.absorb_results([*paths.first(2), expired], processes: 3, ignore_timeout: true)

      expect(command_names).to contain_exactly("shard0", "shard1", "stale")
    end

    it "fans out the smallest split there is", if: FORK_SUPPORTED do
      expect(described_class.absorb_results(paths.first(2), processes: 2, ignore_timeout: true))
        .to eq(SimpleCov::ResultMerger.absorb_results(paths.first(2), ignore_timeout: true))
    end

    it "returns nil when a single process was requested" do
      expect(described_class.absorb_results(paths, processes: 1)).to be_nil
    end

    it "returns nil when there is only one resultset to merge" do
      expect(described_class.absorb_results(paths.first(1), processes: 4)).to be_nil
    end

    it "returns nil when the runtime cannot fork" do
      without_fork

      expect(described_class.absorb_results(paths, processes: 4)).to be_nil
    end
  end

  describe ".collect_payloads", if: FORK_SUPPORTED do
    context "when a worker exits cleanly having shipped no payload" do
      let(:collection) { collecting([silent_worker]) }

      it "refuses the batch" do
        expect(collection.first).to be_nil
      end

      it "counts the workers that failed" do
        expect(collection.last).to include("parallel merge did not complete (0 of 1 workers failed)")
      end
    end

    context "when only some workers shipped" do
      let(:collection) { collecting([shipping_worker(paths.first(1)), silent_worker]) }

      it "refuses the batch" do
        expect(collection.first).to be_nil
      end

      it "counts the workers that failed" do
        expect(collection.last).to include("parallel merge did not complete (0 of 2 workers failed)")
      end
    end

    context "when a worker that shipped a whole payload failed" do
      let(:collection) { collecting([failing_worker(paths.first(1))]) }

      it "refuses the payload" do
        expect(collection.first).to be_nil
      end

      it "counts the workers that failed" do
        expect(collection.last).to include("parallel merge did not complete (1 of 1 workers failed)")
      end
    end
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
    let(:status) { described_class.run_worker(paths, pipe.last, ignore_timeout: true) }
    let(:payload) do
      raise "the worker reported failure (#{status})" unless status.zero?

      Marshal.load(pipe.first) # rubocop:disable Security/MarshalLoad
    end

    after { pipe.each { |io| io.close unless io.closed? } }

    it "reports success" do
      expect(status).to eq(0)
    end

    it "writes the merged pair" do
      pair, = payload

      expect(pair).to eq(serial)
    end

    it "writes the tracked files the slice carried" do
      _pair, tracked = payload

      expect(tracked).to eq([])
    end

    it "writes a context-map union" do
      _pair, _tracked, context_maps = payload

      expect(context_maps).to be_a(SimpleCov::ContextMap::Union)
    end

    it "writes one context-map entry per resultset" do
      _pair, _tracked, context_maps = payload

      expect(context_maps.entries).to eq(paths.size)
    end

    it "closes the pipe behind the payload it shipped" do
      _reader, writer = pipe

      described_class.run_worker(paths, writer, ignore_timeout: true)

      expect(writer).to be_closed
    end

    context "when the merged pair cannot be shipped back" do
      let(:failed_run) do
        reported = nil
        output = capture_stderr { reported = described_class.run_worker(paths, pipe.last, ignore_timeout: true) }
        [reported, output]
      end

      before { pipe.last.close }

      it "reports failure" do
        expect(failed_run.first).to eq(1)
      end

      it "warns" do
        expect(failed_run.last).to include("parallel merge worker failed: IOError: closed stream")
      end

      it "stays quiet about a failed worker when print_errors is off" do
        output = capture_stderr do
          with_print_errors(false) { described_class.run_worker(paths, pipe.last, ignore_timeout: true) }
        end

        expect(output).to be_empty
      end
    end
  end

  describe ".fan_out", if: FORK_SUPPORTED do
    let(:chunks) { described_class.chunk(paths, 3) }

    context "when a worker dies without shipping its slice" do
      let(:fanning) do
        answer = nil
        output = capture_stderr { answer = fan_out_chunks }
        [answer, output]
      end

      before { allow(described_class).to receive(:run_worker).and_return(1) }

      it "returns nil" do
        expect(fanning.first).to be_nil
      end

      it "warns" do
        expect(fanning.last).to include("parallel merge did not complete (3 of 3 workers failed)")
      end

      it "stays quiet about a failed fan-out when print_errors is off" do
        output = capture_stderr { with_print_errors(false) { fan_out_chunks } }

        expect(output).to be_empty
      end
    end
  end

  describe ".run_in_child" do
    let(:pipe) { IO.pipe }
    let(:reader) { pipe.first }
    let(:writer) { pipe.last }

    before do
      allow(described_class).to receive(:exit!)
      allow(described_class).to receive(:run_worker).and_return(1)

      described_class.run_in_child(reader, writer, paths, true)
    end

    after { writer.close }

    it "closes the read end" do
      expect(reader).to be_closed
    end

    it "exits with the status the worker reports" do
      expect(described_class).to have_received(:exit!).with(1)
    end

    it "hands the worker the slice and the write end" do
      expect(described_class).to have_received(:run_worker).with(paths, writer, ignore_timeout: true)
    end
  end

  describe ".fan_out when the OS refuses a fork" do
    let(:chunks) { described_class.chunk(paths, 3) }

    it "lets the error through rather than merging in this process", if: FORK_SUPPORTED do
      allow(described_class).to receive(:fork).and_raise(Errno::EAGAIN)

      expect { described_class.merge_results(*paths, processes: 3, ignore_timeout: true) }
        .to raise_error(Errno::EAGAIN)
    end

    context "when the refusal comes partway through the fan-out", if: FORK_SUPPORTED do
      let(:spawned) do
        workers = refuse_fork_after(1)
        capture_stderr { suppress(Errno::EAGAIN) { fan_out_chunks } }
        workers
      end

      it "lets the error through" do
        refuse_fork_after(1)

        expect { capture_stderr { fan_out_chunks } }.to raise_error(Errno::EAGAIN)
      end

      it "closes the workers it already spawned" do
        expect(spawned.map { |worker| worker[:reader] }).to all(be_closed)
      end

      it "reaps the workers it already spawned" do
        pid = spawned.first[:pid]

        expect { Process.wait2(pid) }.to raise_error(Errno::ECHILD)
      end
    end

    context "when the refusal comes on a single spawn" do
      let(:pipes) { [] }

      before do
        allow(described_class).to receive(:fork).and_raise(Errno::EAGAIN)
        allow(IO).to receive(:pipe).and_wrap_original do |original|
          original.call.tap { |pair| pipes.replace(pair) }
        end
      end

      it "lets the error through" do
        expect { described_class.spawn_worker(paths, ignore_timeout: true) }.to raise_error(Errno::EAGAIN)
      end

      it "closes the failing spawn's own pipe ends" do
        suppress(Errno::EAGAIN) { described_class.spawn_worker(paths, ignore_timeout: true) }

        expect(pipes).to all(be_closed)
      end
    end

    it "has nothing to close when the pipe itself cannot be created" do
      allow(IO).to receive(:pipe).and_raise(Errno::EMFILE)

      expect { described_class.spawn_worker(paths, ignore_timeout: true) }.to raise_error(Errno::EMFILE)
    end
  end

  describe ".read_payload" do
    let(:pipe) { IO.pipe }

    after { pipe.each { |io| io.close unless io.closed? } }

    it "returns nil for a stream a worker never finished writing" do
      reader, writer = pipe
      writer.write(Marshal.dump([["shard0"], {}]).byteslice(0, 4))
      writer.close

      expect(described_class.read_payload(reader)).to be_nil
    end
  end

  describe ".succeeded?" do
    it "is false for a pid that is not one of our children" do
      expect(described_class.succeeded?(Process.pid)).to be false
    end

    it "judges the worker it was asked about, not whichever exits first", if: FORK_SUPPORTED do
      slow = fork { sleep(0.5) && exit!(1) }
      quick = fork { exit!(0) }

      expect(described_class.succeeded?(slow)).to be false
    ensure
      Process.wait2(quick) if quick
    end
  end

  describe "WorkerPayload" do
    let(:worker_payload) { SimpleCov::ParallelResultMerger::WorkerPayload }

    let(:built) do
      map = SimpleCov::ContextMap.new
      map.record("spec/a_spec.rb:1", lib_file => 0b1)
      slice = [write_resultset("mapped", {}, tracked_files: ["tracked.rb"], contexts: map.to_h)]
      worker_payload.build(slice, ignore_timeout: true)
    end
    let(:payload) do
      union = SimpleCov::ContextMap::Union.new
      union.absorb_entry("contexts" => SimpleCov::ContextMap.new.to_h)
      [:pair, ["tracked.rb"], union]
    end
    let(:tracked_files) { Set.new }
    let(:context_maps) { SimpleCov::ContextMap::Union.new }

    it "builds the pair the slice merges to" do
      pair, = built

      expect(pair.first).to eq(["mapped"])
    end

    it "builds the slice's tracked files" do
      _pair, tracked = built

      expect(tracked).to eq(["tracked.rb"])
    end

    it "builds the slice's context-map union" do
      _pair, _tracked, slice_maps = built

      expect(slice_maps.map.contexts).to eq(["spec/a_spec.rb:1"])
    end

    it "exposes a payload's pair" do
      expect(worker_payload.pair(payload)).to eq(:pair)
    end

    context "when a payload is folded into the parent's accumulators" do
      before { worker_payload.absorb(payload, tracked_files, context_maps) }

      it "folds in the payload's tracked files" do
        expect(tracked_files).to eq(Set["tracked.rb"])
      end

      it "folds in the payload's context maps" do
        expect(context_maps.carrying).to eq(1)
      end
    end
  end

  private

  def lib_file
    File.expand_path("/proj/lib/thing.rb")
  end

  def mapped_resultsets
    Array.new(3) do |index|
      map = SimpleCov::ContextMap.new
      map.record("spec/w#{index}_spec.rb:1", lib_file => 1 << index)
      write_resultset("m#{index}", {}, contexts: map.to_h)
    end
  end

  def record_readers(readers)
    allow(described_class).to receive(:spawn_worker).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap { |worker| readers << worker[:reader] }
    end
  end

  def collecting(workers)
    payloads = nil
    output = capture_stderr { payloads = described_class.send(:collect_payloads, workers) }
    [payloads, output]
  end

  def silent_worker
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      exit!(0)
    end
    writer.close
    {pid: pid, reader: reader}
  end

  def shipping_worker(chunk)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      exit!(described_class.run_worker(chunk, writer, ignore_timeout: true))
    end
    writer.close
    {pid: pid, reader: reader}
  end

  def failing_worker(chunk)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      described_class.run_worker(chunk, writer, ignore_timeout: true)
      exit!(1)
    end
    writer.close
    {pid: pid, reader: reader}
  end

  def fan_out_chunks
    described_class.fan_out(chunks, ignore_timeout: true, tracked_files: Set.new,
      context_maps: SimpleCov::ContextMap::Union.new)
  end

  def write_resultset(command_name, coverage, outdated: false, tracked_files: nil, contexts: nil)
    timestamp = Time.now.to_i - (outdated ? SimpleCov.merge_timeout * 2 : 0)
    path = File.join(resultset_dir, ".resultset-#{command_name}.json")
    entry = {"coverage" => coverage, "timestamp" => timestamp}
    entry["tracked_files"] = tracked_files if tracked_files
    entry["contexts"] = contexts if contexts
    File.write(path, JSON.generate(command_name => entry))
    path
  end

  def refuse_fork_after(count)
    spawned = []
    allow(described_class).to receive(:spawn_worker).and_wrap_original do |original, *args, **options|
      raise Errno::EAGAIN if spawned.size >= count

      spawned << original.call(*args, **options)
      spawned.last
    end
    spawned
  end

  def without_fork
    allow(Process).to receive(:respond_to?).and_call_original
    allow(Process).to receive(:respond_to?).with(:fork).and_return(false)
  end

  def with_print_errors(value)
    previous = SimpleCov.print_errors
    SimpleCov.print_errors value
    yield
  ensure
    SimpleCov.print_errors previous
  end
end
