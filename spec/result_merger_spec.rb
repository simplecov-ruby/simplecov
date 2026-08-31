# frozen_string_literal: true

require "helper"
require "tempfile"
require "timeout"

RSpec.describe SimpleCov::ResultMerger do
  around do |example|
    previous_dir = SimpleCov.coverage_dir
    Dir.mktmpdir("simplecov-resultset") do |dir|
      SimpleCov.coverage_dir(dir)
      example.run
    ensure
      SimpleCov.coverage_dir(previous_dir)
    end
  end

  before do
    FileUtils.mkdir_p(File.dirname(described_class.resultset_path))
  end

  after do
    FileUtils.rm_f(described_class.resultset_path)
  end

  let(:first_resultset) do
    {
      source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]},
      source_fixture("app/models/user.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]},
      source_fixture("app/controllers/sample_controller.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]},
      source_fixture("resultset1.rb") => {"lines" => [1, 1, 1, 1]},
      source_fixture("parallel_tests.rb") => {"lines" => [nil, 0, nil, 0]},
      source_fixture("conditionally_loaded_1.rb") => {"lines" => [nil, 0, 1]}
    }
  end

  let(:second_resultset) do
    {
      source_fixture("sample.rb") => {"lines" => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]},
      source_fixture("app/models/user.rb") => {"lines" => [nil, 1, 5, 1, nil, nil, 1, 0, nil, nil]},
      source_fixture("app/controllers/sample_controller.rb") => {"lines" => [nil, 3, 1, nil, nil, nil, 1, 0, nil, nil]},
      source_fixture("resultset2.rb") => {"lines" => [nil, 1, 1, nil]},
      source_fixture("parallel_tests.rb") => {"lines" => [nil, nil, 0, 0]},
      source_fixture("conditionally_loaded_2.rb") => {"lines" => [nil, 0, 1]}
    }
  end

  let(:merged_resultsets) do
    {
      source_fixture("sample.rb") => {"lines" => [1, 1, 2, 2, nil, nil, 2, 2, nil, nil]},
      source_fixture("app/models/user.rb") => {"lines" => [nil, 2, 6, 2, nil, nil, 2, 0, nil, nil]},
      source_fixture("app/controllers/sample_controller.rb") => {"lines" => [nil, 4, 2, 1, nil, nil, 2, 0, nil, nil]},
      source_fixture("resultset1.rb") => {"lines" => [1, 1, 1, 1]},
      source_fixture("parallel_tests.rb") => {"lines" => [nil, 0, 0, 0]},
      source_fixture("conditionally_loaded_1.rb") => {"lines" => [nil, 0, 1]},
      source_fixture("resultset2.rb") => {"lines" => [nil, 1, 1, nil]},
      source_fixture("conditionally_loaded_2.rb") => {"lines" => [nil, 0, 1]}
    }
  end

  let(:first_result) { SimpleCov::Result.new(first_resultset, command_name: "result1") }
  let(:second_result) { SimpleCov::Result.new(second_resultset, command_name: "result2") }

  describe "the shape of an injected file" do
    let(:loaded) { source_fixture("resultset1.rb") }
    let(:never_loaded) { source_fixture("sample.rb") }

    def injected(coverage)
      result = described_class.send(:create_result, ["merged"], coverage, tracked_files: Set[never_loaded])
      result.original_result.fetch(never_loaded)
    end

    it "synthesizes tuples when the merged files carry them, whatever this process measures",
       if: SimpleCov::StaticCoverageExtractor.available? do
      allow(SimpleCov).to receive_messages(branch_coverage?: false, method_coverage?: false)

      entry = injected(loaded => {"lines" => [1, 1], "methods" => {}})

      expect(entry["methods"]).not_to be_empty
    end

    it "synthesizes tuples when the merged files carry branches alone",
       if: SimpleCov::StaticCoverageExtractor.available? do
      allow(SimpleCov).to receive_messages(branch_coverage?: false, method_coverage?: false)

      entry = injected(loaded => {"lines" => [1, 1], "branches" => {}})

      expect(entry["methods"]).not_to be_empty
    end

    it "gives a simulated file lines when the merged files carry them" do
      allow(SimpleCov).to receive(:line_coverage?).and_return(false)

      expect(injected(loaded => {"lines" => [1, 1]})).to have_key("lines")
    end

    it "leaves them empty when the merged files carry none",
       if: SimpleCov::StaticCoverageExtractor.available? do
      allow(SimpleCov).to receive_messages(branch_coverage?: true, method_coverage?: true)

      entry = injected(loaded => {"lines" => [1, 1]})

      expect(entry["methods"]).to be_empty
    end

    it "falls back to this process's criteria when the merge carried no files" do
      allow(SimpleCov).to receive_messages(line_coverage?: false, branch_coverage?: true, method_coverage?: false)

      result = described_class.send(:create_result, ["merged"], {}, tracked_files: Set[never_loaded])

      expect(result.original_result.fetch(never_loaded)).not_to have_key("lines")
    end

    it "takes lines from this process's criteria too when the merge carried no files" do
      allow(SimpleCov).to receive_messages(line_coverage?: true, branch_coverage?: false, method_coverage?: false)

      result = described_class.send(:create_result, ["merged"], {}, tracked_files: Set[never_loaded])

      expect(result.original_result.fetch(never_loaded)).to have_key("lines")
    end
  end

  describe "warning about merged files that are no longer on disk" do
    it "names what the merge dropped" do
      allow(SimpleCov).to receive(:final_result_process?).and_return(true)

      stderr = capture_stderr do
        described_class.send(:create_result, ["merged"], {"/gone/missing.rb" => {"lines" => [1]}}, tracked_files: [])
      end

      expect(stderr).to include("SimpleCov dropped all 1 source file(s)").and include("/gone/missing.rb")
    end
  end

  describe "the merged command name" do
    def named(command_names)
      described_class.send(:create_result, command_names, {}, tracked_files: [])
    end

    it "dedupes repeated names" do
      expect(named(%w[RSpec RSpec RSpec]).command_name).to eq "RSpec"
    end

    it "sorts distinct names and drops empties" do
      expect(named(["b", "", "a", "b"]).command_name).to eq "a, b"
    end

    it "carries the distinct names for presentation" do
      expect(named(%w[b a b]).command_names).to eq %w[a b]
    end
  end

  describe "tracked paths from an expired resultset" do
    let(:never_loaded) { source_fixture("resultset1.rb") }

    before do
      FileUtils.rm_f(described_class.resultset_path)
      stale = SimpleCov::Result.new({source_fixture("sample.rb") => {"lines" => [nil, 1]}},
                                    command_name: "stale", tracked_files: [never_loaded])
      described_class.store_result(outdated(stale))
      fresh = SimpleCov::Result.new({source_fixture("sample.rb") => {"lines" => [nil, 1]}},
                                    command_name: "fresh")
      described_class.store_result(fresh)
    end

    it "does not simulate a file only the expired run tracked" do
      merged = nil
      capture_stderr { merged = described_class.merged_result }

      expect(merged.original_result.keys).not_to include(never_loaded)
    end
  end

  describe "injecting unloaded files at the merge point" do
    let(:loaded) { source_fixture("sample.rb") }
    let(:never_loaded) { source_fixture("resultset1.rb") }
    let(:coverage) { {loaded => {"lines" => [nil, 1, 1, 0]}} }

    it "simulates a tracked file no contributing process loaded" do
      result = described_class.send(:create_result, ["merged"], coverage,
                                    tracked_files: Set[loaded, never_loaded])

      expect(result.original_result.keys).to include(never_loaded)
      expect(result.files.find { |f| f.filename == never_loaded }).to be_not_loaded
    end

    it "flags a simulated file that carries no line data" do
      result = described_class.send(:create_result, ["merged"],
                                    {loaded => {"branches" => {}, "methods" => {}}},
                                    tracked_files: Set[never_loaded])

      expect(result.files.find { |f| f.filename == never_loaded }).to be_not_loaded
    end

    it "leaves a file some process loaded alone" do
      result = described_class.send(:create_result, ["merged"], coverage,
                                    tracked_files: Set[loaded, never_loaded])

      expect(result.original_result[loaded]).to eq(coverage[loaded])
      expect(result.files.find { |f| f.filename == loaded }).not_to be_not_loaded
    end

    it "injects nothing when the resultsets recorded no tracked files" do
      result = described_class.send(:create_result, ["merged"], coverage, tracked_files: [])

      expect(result.original_result.keys).to contain_exactly(loaded)
    end

    it "carries the tracked paths onto the merged result for a later collate" do
      result = described_class.send(:create_result, ["merged"], coverage,
                                    tracked_files: Set[loaded, never_loaded])

      expect(result.tracked_files).to contain_exactly(loaded, never_loaded)
      expect(result.to_hash["merged"]["tracked_files"]).to contain_exactly(loaded, never_loaded)
    end

    it "leaves an already-simulated file from an older resultset untouched" do
      already_simulated = {never_loaded => {"lines" => [0, 0, nil, 0]}}
      result = described_class.send(:create_result, ["merged"], coverage.merge(already_simulated),
                                    tracked_files: Set[never_loaded])

      expect(result.original_result[never_loaded]).to eq(already_simulated[never_loaded])
    end
  end

  describe ".tracked_files_in a resultset" do
    it "unions what every contributing process was told to track" do
      resultset = {
        "a" => {"coverage" => {}, "tracked_files" => ["/x/one.rb", "/x/two.rb"]},
        "b" => {"coverage" => {}, "tracked_files" => ["/x/two.rb", "/x/three.rb"]}
      }

      expect(SimpleCov::ResultMerger::UnloadedFiles.tracked_in(resultset))
        .to eq(Set["/x/one.rb", "/x/two.rb", "/x/three.rb"])
    end

    it "is empty for resultsets written before tracked paths were recorded" do
      resultset = {"a" => {"coverage" => {}, "timestamp" => 1}}

      expect(SimpleCov::ResultMerger::UnloadedFiles.tracked_in(resultset)).to be_empty
    end
  end

  describe "the criteria the merged coverage carries" do
    let(:unloaded_files) { SimpleCov::ResultMerger::UnloadedFiles }

    it "answers yes when any merged file carries the criterion" do
      coverage = {"a.rb" => {"lines" => []}, "b.rb" => {"lines" => [], "branches" => {}}}

      expect(unloaded_files.carries?(coverage, "branches")).to be true
    end

    it "answers no for a criterion whose key is present but empty" do
      expect(unloaded_files.carries?({"a.rb" => {"lines" => nil}}, "lines")).to be false
    end

    it "answers from the configuration when the merge carried no files" do
      allow(SimpleCov).to receive(:branch_coverage?).and_return(true)
      expect(unloaded_files.carries?({}, "branches")).to be true

      allow(SimpleCov).to receive(:branch_coverage?).and_return(false)
      expect(unloaded_files.carries?({}, "branches")).to be false
    end
  end

  describe "the tracked paths a merge injects" do
    let(:unloaded_files) { SimpleCov::ResultMerger::UnloadedFiles }

    it "leaves a combined entry alone when neither side tracked anything" do
      expect(unloaded_files.carry_tracked({"coverage" => {}}, {}, {})).to eq("coverage" => {})
    end

    it "converts the paths before the injector sees them" do
      never_loaded = source_fixture("resultset1.rb")
      coverage = {source_fixture("sample.rb") => {"lines" => [nil, 1]}}

      injected, added = unloaded_files.inject(coverage, [never_loaded].each)

      expect(added).to eq(Set[never_loaded])
      expect(injected.keys).to contain_exactly(source_fixture("sample.rb"), never_loaded)
    end
  end

  describe "collecting what each resultset contributed" do
    let(:surviving) do
      {
        "a" => {"coverage" => {}, "tracked_files" => ["/x/one.rb"]},
        "b" => {"coverage" => {}, "tracked_files" => ["/x/two.rb"]}
      }
    end

    it "gathers the tracked paths into the set it was handed" do
      into = Set.new

      SimpleCov::ResultMerger::UnloadedFiles.collector(into).call(surviving)

      expect(into).to eq(Set["/x/one.rb", "/x/two.rb"])
    end

    it "feeds the tracked paths as well as the map union" do
      tracked = Set.new

      described_class.entry_collector(tracked, SimpleCov::ContextMap::Union.new).call(surviving)

      expect(tracked).to eq(Set["/x/one.rb", "/x/two.rb"])
    end
  end

  describe "folding the runs of several resultsets together" do
    let(:one) { [["result1"], {"a.rb" => {"lines" => [1, nil]}}] }
    let(:two) { [["result2"], {"a.rb" => {"lines" => [1, 1]}}] }

    it "answers an unnamed run and no coverage when there is nothing to fold" do
      expect(described_class.merge_coverage).to eq([[""], nil])
    end

    it "hands back the one run it was given, unfolded" do
      expect(described_class.merge_coverage(one)).to be(one)
    end

    it "folds two runs into one" do
      expect(described_class.merge_coverage(one, two)).to eq([%w[result1 result2], {"a.rb" => {"lines" => [2, 1]}}])
    end
  end

  describe "dropping the results that are past the merge timeout" do
    let(:fresh) { {"timestamp" => Time.now.to_f, "coverage" => {}} }
    let(:expired) { {"timestamp" => Time.now.to_f - (SimpleCov.merge_timeout * 2), "coverage" => {}} }

    it "hands back the results it was given when every one of them is fresh" do
      results = {"a" => fresh, "b" => fresh}
      kept = nil

      stderr = capture_stderr { kept = described_class.drop_expired_results(results) }

      expect(kept).to be(results)
      expect(stderr).to be_empty
    end

    it "keeps the fresh results and names the expired ones in sorted order" do
      results = {"z-stale" => expired, "current" => fresh, "a-stale" => expired}
      kept = nil

      stderr = capture_stderr { kept = described_class.drop_expired_results(results) }

      expect(kept).to eq("current" => fresh)
      expect(stderr).to eq(
        "[SimpleCov]: Excluded 2 result(s) older than merge_timeout " \
        "(#{SimpleCov.merge_timeout}s) from the merged report: a-stale, z-stale. " \
        "Increase SimpleCov.merge_timeout to include them.\n"
      )
    end
  end

  describe "carrying the context maps of a combined entry" do
    let(:contexts) { SimpleCov::ResultMerger::Contexts }
    let(:path) { source_fixture("sample.rb") }

    def recorded(test_id, bitmap)
      {"contexts" => SimpleCov::ContextMap.new.record(test_id, path => bitmap).to_h}
    end

    it "unions the maps when both entries carry one" do
      incoming = recorded("spec/b_spec.rb:2", 0b10)

      carried = contexts.carry(incoming, recorded("spec/a_spec.rb:1", 0b1), incoming)

      map = SimpleCov::ContextMap.from_hash(carried.fetch("contexts"))
      expect(map.covering(path, 1)).to eq(["spec/a_spec.rb:1"])
      expect(map.covering(path, 2)).to eq(["spec/b_spec.rb:2"])
    end

    it "drops the map when only the incoming entry carries one" do
      incoming = recorded("spec/a_spec.rb:1", 0b1)

      expect(contexts.carry(incoming, {}, incoming)).to eq({})
    end

    it "drops the map when only the existing entry carries one" do
      existing = recorded("spec/a_spec.rb:1", 0b1)

      expect(contexts.carry({"coverage" => {}}, existing, {})).to eq("coverage" => {})
    end
  end

  describe "recognizing an entry written by a concurrent runner" do
    before { allow(SimpleCov).to receive(:process_start_time).and_return(Time.at(100.5)) }

    it "answers false for an entry that is not a hash" do
      expect(described_class.concurrent_runner_entry?([["timestamp", 100.75]])).to be false
    end

    it "ignores an incoming entry that is not a hash instead of reading a run id off it" do
      expect(described_class.concurrent_runner_entry?({"timestamp" => 100.75}, [%w[run_id x]])).to be true
    end

    it "counts an entry of our own run stamped at our start time" do
      allow(SimpleCov::RunIdentity).to receive(:authoritative?).and_return(false)
      entry = {"run_id" => "r", "timestamp" => 100.5}

      expect(described_class.concurrent_runner_entry?(entry, "run_id" => "r")).to be true
    end

    it "answers false for a current-run entry that is not a hash" do
      expect(described_class.current_run_entry?([%w[run_id r]], "r", Time.at(100.5))).to be false
    end

    it "answers false for an entry carrying no timestamp at all" do
      expect(described_class.fresh_entry?({}, Time.at(100.5))).to be false
      expect(described_class.written_after_start?({}, Time.at(100.5))).to be false
    end

    it "counts an entry stamped at our start time as fresh, but not as later" do
      expect(described_class.fresh_entry?({"timestamp" => 100.5}, Time.at(100.5))).to be true
      expect(described_class.written_after_start?({"timestamp" => 100.5}, Time.at(100.5))).to be false
    end

    it "answers false for a timestamp that is not a number" do
      expect(described_class.written_after_start?({"timestamp" => "100.9"}, Time.at(100.5))).to be false
    end
  end

  describe "tracked paths from a stored resultset" do
    it "simulates a file the stored run tracked and nobody loaded" do
      never_loaded = source_fixture("resultset1.rb")
      described_class.store_result(
        SimpleCov::Result.new({source_fixture("sample.rb") => {"lines" => [nil, 1]}},
                              command_name: "RSpec", tracked_files: [never_loaded])
      )

      merged = described_class.merged_result

      expect(merged.original_result.keys).to include(never_loaded)
      expect(merged.tracked_files).to eq([never_loaded])
    end
  end

  describe "not-loaded files in a merged result" do
    subject(:result) { described_class.send(:create_result, ["merged"], coverage, tracked_files: []) }

    let(:executed) { source_fixture("sample.rb") }
    let(:never_executed) { source_fixture("resultset1.rb") }
    let(:coverage) do
      {
        executed => {"lines" => [nil, 1, 1, 0]},
        never_executed => {"lines" => [0, 0, nil, 0]}
      }
    end

    def file(path)
      result.files.find { |source_file| source_file.filename == path }
    end

    it "flags a file no contributing process executed" do
      expect(file(never_executed)).to be_not_loaded
    end

    it "leaves a file some process executed alone" do
      expect(file(executed)).not_to be_not_loaded
    end

    it "reports 0% rather than 100% for a never-loaded file with no branch data" do
      expect(file(never_executed).coverage_statistics[:branch]&.percent).to eq(0.0)
    end

    context "when the results carry no line data" do
      let(:coverage) do
        {
          executed => {"branches" => {}, "methods" => {}},
          never_executed => {"branches" => {}, "methods" => {}}
        }
      end

      it "flags nothing rather than mistaking loaded files for unloaded ones" do
        expect(result.files).to all(satisfy { |source_file| !source_file.not_loaded? })
      end
    end

    context "when a loaded file has no relevant lines" do
      let(:comment_only) { source_fixture("never.rb") }
      let(:coverage) do
        {
          executed => {"lines" => [nil, 1, 1, 0]},
          comment_only => {"lines" => [nil, nil]}
        }
      end

      it "does not flag it" do
        expect(file(comment_only)).not_to be_not_loaded
      end

      it "keeps its statistics off the #902 not-loaded rule" do
        expect(file(comment_only).coverage_statistics[:branch]&.percent).to eq(100.0)
      end
    end

    context "when a merged entry has a nil lines value" do
      let(:coverage) { {executed => {"lines" => nil, "branches" => {}, "methods" => {}}} }

      it "does not flag it" do
        expect(file(executed)).not_to be_not_loaded
      end
    end
  end

  describe "resultset handling" do
    it "puts the resultset in the coverage directory" do
      expect(described_class.resultset_path).to eq(File.join(SimpleCov.coverage_path, ".resultset.json"))
    end

    it "returns an empty hash when the resultset cache file is empty" do
      File.write(described_class.resultset_path, "")

      stderr = capture_stderr { expect(described_class.read_resultset).to eq({}) }

      expect(stderr).to be_empty
    end

    it "returns an empty hash when the resultset cache file holds only whitespace" do
      File.write(described_class.resultset_path, "  \n\t\n")

      stderr = capture_stderr { expect(described_class.read_resultset).to eq({}) }

      expect(stderr).to be_empty
    end

    it "returns an empty hash when the resultset cache file is not present" do
      FileUtils.rm_f(described_class.resultset_path)
      expect(described_class.read_resultset).to be_empty
    end

    it "warns and returns an empty hash when the resultset is malformed JSON" do
      File.write(described_class.resultset_path, "this is not json {")
      stderr = capture_stderr { expect(described_class.read_resultset).to be_empty }
      expect(stderr).to include("Parsing JSON content of resultset file failed")
    end

    it "warns about a resultset truncated to a single byte" do
      File.write(described_class.resultset_path, "{")
      stderr = capture_stderr { expect(described_class.read_resultset).to be_empty }
      expect(stderr).to include("Parsing JSON content of resultset file failed")
    end

    it "warns and returns an empty hash when the resultset is valid JSON but not an object" do
      File.write(described_class.resultset_path, "[1, 2]")
      stderr = capture_stderr { expect(described_class.read_resultset).to be_empty }
      expect(stderr).to include("Parsing JSON content of resultset file failed")
    end

    it "warns and returns an empty hash for a top-level array of entries" do
      File.write(described_class.resultset_path,
                 JSON.dump([["RSpec", {"timestamp" => Time.now.to_f, "coverage" => {}}]]))

      stderr = capture_stderr { expect(described_class.read_resultset).to eq({}) }

      expect(stderr).to include("Parsing JSON content of resultset file failed")
    end

    it "keeps treating a null resultset as empty, without a warning" do
      File.write(described_class.resultset_path, "null")
      stderr = capture_stderr { expect(described_class.read_resultset).to be_empty }
      expect(stderr).to be_empty
    end

    it "warns and drops malformed entries while keeping well-formed ones" do
      malformed = {
        "good" => {"timestamp" => Time.now.to_f, "coverage" => {}},
        "null-entry" => nil,
        "array-entry" => [1, 2],
        "no-timestamp" => {"coverage" => {}},
        "text-timestamp" => {"timestamp" => "1700000000", "coverage" => {}},
        "no-coverage" => {"timestamp" => Time.now.to_f},
        "string-coverage" => {"timestamp" => Time.now.to_f, "coverage" => "x"}
      }
      File.write(described_class.resultset_path, JSON.dump(malformed))

      stderr = capture_stderr { expect(described_class.read_resultset.keys).to eq(["good"]) }

      expect(stderr).to eq("[SimpleCov]: Warning! Ignoring malformed resultset entries: array-entry, " \
                           "no-coverage, no-timestamp, null-entry, string-coverage, text-timestamp\n")
    end

    it "merges through a resultset containing a malformed entry instead of crashing" do
      File.write(described_class.resultset_path, JSON.dump("broken" => nil))
      result = SimpleCov::Result.new({source_fixture("sample.rb") => {"lines" => [nil, 1]}},
                                     command_name: "RSpec")

      capture_stderr { expect(described_class.store_result(result)).to be true }

      expect(described_class.read_resultset.keys).to eq(["RSpec"])
    end
  end

  describe ".worker_identities_for_run" do
    it "returns distinct identified workers from only the requested run" do
      allow(SimpleCov::RunIdentity).to receive(:authoritative?).and_return(true)
      started_at = Time.now
      resultset = {
        "worker 1" => {"run_id" => "current", "worker_id" => "1"},
        "worker 1 child" => {"run_id" => "current", "worker_id" => "1"},
        "worker 2" => {"run_id" => "current", "worker_id" => "2"},
        "stale" => {"run_id" => "old", "worker_id" => "3"},
        "legacy current" => {"timestamp" => started_at.to_f + 1},
        "malformed" => nil
      }

      expect(described_class.worker_identities_for_run(resultset, "current", started_at))
        .to contain_exactly([:worker, "1"], [:worker, "2"], [:legacy, "legacy current"])
    end

    it "cannot alias a worker id to a legacy entry's synthesized identity" do
      allow(SimpleCov::RunIdentity).to receive(:authoritative?).and_return(true)
      resultset = {
        "spoofing worker" => {"run_id" => "current", "worker_id" => "legacy:suite"},
        "suite" => {"timestamp" => 100.75}
      }

      expect(described_class.worker_identities_for_run(resultset, "current", Time.at(100.5)).size).to eq(2)
    end

    it "counts numeric and string spellings of one worker id once" do
      allow(SimpleCov::RunIdentity).to receive(:authoritative?).and_return(true)
      resultset = {
        "worker 1 parent" => {"run_id" => "current", "worker_id" => 1},
        "worker 1 child" => {"run_id" => "current", "worker_id" => "1"}
      }

      expect(described_class.worker_identities_for_run(resultset, "current", Time.now)).to eq([[:worker, "1"]])
    end

    it "applies precise freshness to a weak parent-process run identity" do
      allow(SimpleCov::RunIdentity).to receive(:authoritative?).and_return(false)
      resultset = {
        "stale" => {"run_id" => "parallel-parent:1", "worker_id" => "1", "timestamp" => 100.25},
        "current" => {"run_id" => "parallel-parent:1", "worker_id" => "2", "timestamp" => 100.75}
      }

      expect(described_class.worker_identities_for_run(resultset, "parallel-parent:1", Time.at(100.5)))
        .to eq([[:worker, "2"]])
    end

    it "ignores a legacy entry whose timestamp is not numeric" do
      resultset = {"garbage" => {"timestamp" => {}}}

      expect(described_class.worker_identities_for_run(resultset, "current", Time.at(100.5))).to be_empty
    end
  end

  describe ".concurrent_runner_entry?" do
    it "uses timestamp freshness when no incoming run identity is available" do
      allow(SimpleCov).to receive(:process_start_time).and_return(Time.at(100.5))

      expect(described_class).to be_concurrent_runner_entry("timestamp" => 100.75)
    end
  end

  describe "storing a live result over a concurrent entry with the same command name" do
    it "combines counts for files both writers carry" do
      allow(SimpleCov).to receive(:process_start_time).and_return(Time.at(0))
      stored = SimpleCov::Result.new(
        {source_fixture("sample.rb") => {"lines" => [nil, 1, 0, 1, nil, nil, 1, 1, nil, nil]}},
        command_name: "shared"
      )
      live = SimpleCov::Result.new(
        {source_fixture("sample.rb") => {lines: [nil, 5, 1, 0, nil, nil, 1, 1, nil, nil]}},
        command_name: "shared"
      )

      described_class.store_result(stored)
      described_class.store_result(live)

      combined = described_class.read_resultset.dig("shared", "coverage", source_fixture("sample.rb"))
      expect(combined["lines"]).to eq [nil, 6, 1, 1, nil, nil, 2, 2, nil, nil]
    end
  end

  describe "basic workings with 2 resultsets" do
    before do
      FileUtils.rm_f(described_class.resultset_path)
      described_class.store_result(first_result)
      described_class.store_result(second_result)
    end

    it "has stored both results in the resultset_path JSON file" do
      stored = JSON.parse(File.read(described_class.resultset_path))
      expect(stored.keys.sort).to eq %w[result1 result2]
      expect(stored.each_value).to all(include("coverage", "timestamp"))
    end

    it "returns a hash containing keys ['result1' and 'result2'] for resultset" do
      expect(described_class.read_resultset.keys.sort).to eq %w[result1 result2]
    end

    it "returns proper values for merged_result" do
      result = described_class.merged_result

      expect_resultset_1_and_2_merged(result.to_hash)
    end

    context "with second result way above the merge_timeout" do
      let(:second_result) { outdated(super()) }

      before do
        described_class.store_result(second_result)
      end

      it "has only one result in SimpleCov::ResultMerger.results" do
        merged_coverage = described_class.merged_result

        expect(merged_coverage.command_name).to eq "result1"
        expect(merged_coverage.original_result).to eq first_resultset
      end
    end
  end

  describe ".merge_and_store" do
    let(:resultset_prefix) { File.join(SimpleCov.coverage_path, "test_resultset") }
    let(:resultset1_path) { "#{resultset_prefix}1.json" }
    let(:resultset2_path) { "#{resultset_prefix}2.json" }

    describe "merging behavior" do
      before do
        store_result(first_result, path: resultset1_path)
        store_result(second_result, path: resultset2_path)
      end

      after do
        FileUtils.rm Dir.glob("#{resultset_prefix}*.json")
      end

      it "absorbs results without a block" do
        command_names, coverage = described_class.absorb_results(
          [resultset1_path, resultset2_path], ignore_timeout: true
        )

        expect(command_names).to contain_exactly("result1", "result2")
        expect(coverage.keys).to include(source_fixture("sample.rb"))
      end

      context "when 2 normal results" do
        it "correctly merges the 2 results" do
          result = described_class.merge_and_store(resultset1_path, resultset2_path)
          expect_resultset_1_and_2_merged(result.to_hash)
        end

        it "has the result stored" do
          described_class.merge_and_store(resultset1_path, resultset2_path)

          expect_resultset_1_and_2_merged(described_class.read_resultset)
        end
      end

      context "when 1 resultset is outdated" do
        let(:first_result) { outdated(super()) }

        it "completely omits the result from the merge" do
          stderr = capture_stderr do
            result_hash = described_class.merge_and_store(resultset1_path, resultset2_path).to_hash

            expect(result_hash.keys).to eq ["result2"]

            merged_coverage = result_hash.fetch("result2").fetch("coverage")
            expect(merged_coverage).to eq(second_resultset)
          end
          expect(stderr).to include("[SimpleCov]")
          expect(stderr).to include("merge_timeout")
          expect(stderr).to include("result1")
        end

        it "stays silent when print_errors is disabled" do
          allow(SimpleCov).to receive(:print_errors).and_return(false)

          stderr = capture_stderr do
            described_class.merge_and_store(resultset1_path, resultset2_path)
          end

          expect(stderr).to be_empty
        end

        it "includes it when we say ignore_timeout: true" do
          stderr = capture_stderr do
            result_hash = described_class.merge_and_store(
              resultset1_path, resultset2_path, ignore_timeout: true
            ).to_hash

            expect_resultset_1_and_2_merged(result_hash)
          end
          expect(stderr).to be_empty
        end
      end

      context "when both resultsets outdated" do
        let(:first_result) { outdated(super()) }
        let(:second_result) { outdated(super()) }

        it "completely omits the result from the merge" do
          allow(described_class).to receive(:store_result)

          result = described_class.merge_and_store(resultset1_path, resultset2_path)

          expect(result).to be_nil
          expect(described_class).not_to have_received(:store_result)
        end

        it "includes both when we say ignore_timeout: true" do
          result_hash = described_class.merge_and_store(resultset1_path, resultset2_path, ignore_timeout: true).to_hash

          expect_resultset_1_and_2_merged(result_hash)
        end
      end
    end

    context "with method coverage", if: SimpleCov.method_coverage_supported? do
      let(:method_lines) { [1, 1, 1, 1, nil, nil, 1, nil, 1, 1, nil, nil, 1, 0, nil, nil, nil, 1] }
      let(:method_resultset1_path) { "#{resultset_prefix}_method1.json" }
      let(:method_resultset2_path) { "#{resultset_prefix}_method2.json" }

      before do
        SimpleCov.enable_coverage :method
      end

      after do
        SimpleCov.clear_coverage_criteria
        FileUtils.rm Dir.glob("#{resultset_prefix}_method*.json")
      end

      it "correctly merges method coverage across results" do
        rs1 = {
          source_fixture("methods.rb") => {
            "lines" => method_lines,
            "methods" => {["A", :method1, 2, 2, 5, 5] => 1, ["A", :method2, 9, 2, 11, 5] => 0}
          }
        }
        rs2 = {
          source_fixture("methods.rb") => {
            "lines" => method_lines,
            "methods" => {["A", :method1, 2, 2, 5, 5] => 0, ["A", :method2, 9, 2, 11, 5] => 3}
          }
        }

        r1 = SimpleCov::Result.new(rs1, command_name: "r1")
        r2 = SimpleCov::Result.new(rs2, command_name: "r2")

        File.open(method_resultset1_path, "w+") { |f| f.puts JSON.pretty_generate(r1.to_hash) }
        File.open(method_resultset2_path, "w+") { |f| f.puts JSON.pretty_generate(r2.to_hash) }

        result = described_class.merge_and_store(method_resultset1_path, method_resultset2_path)
        methods = result.original_result.fetch(source_fixture("methods.rb"))["methods"]

        expect(methods.values.sort).to eq([1, 3])
      end
    end

    context "when pre 0.18 result format" do
      let(:file_path) { File.join(SimpleCov.coverage_path, "old_resultset.json") }
      let(:content) { {source_fixture("three.rb") => [nil, 1, 2]} }

      before do
        data = {
          "some command name" => {
            "coverage" => content,
            "timestamp" => Time.now.to_i
          }
        }
        File.open(file_path, "w+") do |f|
          f.puts JSON.pretty_generate(data)
        end
      end

      after do
        FileUtils.rm file_path
      end

      it "gets the same content back but under \"lines\"" do
        result = described_class.merge_and_store(file_path)

        expect(result.original_result).to eq(
          source_fixture("three.rb") => {"lines" => [nil, 1, 2]}
        )
      end
    end
  end

  describe ".absorb_results" do
    let(:resultset_prefix) { File.join(SimpleCov.coverage_path, "fold_test_resultset") }
    let(:paths) { [1, 2].map { |index| "#{resultset_prefix}#{index}.json" } }

    before do
      store_result(first_result, path: paths.first)
      store_result(second_result, path: paths.last)
    end

    after do
      FileUtils.rm Dir.glob("#{resultset_prefix}*.json")
    end

    it "combines the resultsets into a command_names / coverage pair" do
      command_names, coverage = described_class.absorb_results(paths, ignore_timeout: true)

      expect(command_names).to eq(%w[result1 result2])
      expect(coverage).to eq(merged_resultsets)
    end

    it "leaves the caller's list of paths alone" do
      described_class.absorb_results(paths, ignore_timeout: true)

      expect(paths).to eq(["#{resultset_prefix}1.json", "#{resultset_prefix}2.json"])
    end

    it "folds each resultset in before reading the next" do
      events = []
      accumulator = SimpleCov::Combine::CoverageAccumulator.new
      allow(SimpleCov::Combine::CoverageAccumulator).to receive(:new).and_return(accumulator)
      allow(accumulator).to receive(:absorb).and_wrap_original do |fold_in, coverage|
        events << :folded
        fold_in.call(coverage)
      end
      read_on_demand = Enumerator.new do |yielder|
        paths.each_with_index do |path, index|
          events << [:read, index]
          yielder << path
        end
      end

      described_class.absorb_results(read_on_demand, ignore_timeout: true) { events << :parsed }

      expect(events).to eq([[:read, 0], :parsed, :folded, [:read, 1], :parsed, :folded])
    end

    context "when both resultsets are past the merge timeout" do
      let(:first_result) { outdated(super()) }
      let(:second_result) { outdated(super()) }

      it "honours the merge timeout when the caller states no preference" do
        command_names = nil
        coverage = nil
        capture_stderr { command_names, coverage = described_class.absorb_results(paths) }

        expect(command_names).to eq(["", ""])
        expect(coverage).to be_nil
      end

      it "keeps both when told to ignore the timeout" do
        command_names, coverage = described_class.absorb_results(paths, ignore_timeout: true)

        expect(command_names).to eq(%w[result1 result2])
        expect(coverage).to eq(merged_resultsets)
      end
    end
  end

  describe ".valid_results" do
    let(:single_path) { File.join(SimpleCov.coverage_path, "valid_results_resultset.json") }

    it "yields the entries that survived to the caller's block" do
      store_result(first_result, path: single_path)
      surviving = nil

      described_class.valid_results(single_path) { |entries| surviving = entries }

      expect(surviving.keys).to eq(["result1"])
    end

    it "drops an expired entry when the caller states no preference" do
      store_result(outdated(first_result), path: single_path)

      command_names = nil
      coverage = nil
      capture_stderr { command_names, coverage = described_class.valid_results(single_path) }

      expect(command_names).to eq([""])
      expect(coverage).to be_nil
    end

    it "keeps an expired entry when told to ignore the timeout" do
      store_result(outdated(first_result), path: single_path)

      command_names, coverage = described_class.valid_results(single_path, ignore_timeout: true)

      expect(command_names).to eq(["result1"])
      expect(coverage).to eq(first_resultset)
    end
  end

  describe ".merge_results" do
    let(:single_path) { File.join(SimpleCov.coverage_path, "merge_results_resultset.json") }

    it "merges a resultset without being told what to do about the timeout" do
      store_result(first_result, path: single_path)

      expect(described_class.merge_results(single_path).original_result).to eq(first_resultset)
    end

    it "keeps an expired resultset when told to ignore the timeout" do
      store_result(outdated(first_result), path: single_path)

      expect(described_class.merge_results(single_path, ignore_timeout: true).original_result).to eq(first_resultset)
    end

    it "injects a file the merged resultset tracked and nobody loaded" do
      never_loaded = source_fixture("resultset1.rb")
      tracked = SimpleCov::Result.new({source_fixture("sample.rb") => {"lines" => [nil, 1]}},
                                      command_name: "result1", tracked_files: [never_loaded])
      store_result(tracked, path: single_path)

      merged = described_class.merge_results(single_path)

      expect(merged.original_result.keys).to include(never_loaded)
      expect(merged.tracked_files).to eq([never_loaded])
    end

    it "carries the per-test map the merged resultset recorded" do
      map = SimpleCov::ContextMap.new
      map.record("spec/a_spec.rb:1", source_fixture("sample.rb") => 0b10)
      mapped = SimpleCov::Result.new({source_fixture("sample.rb") => {"lines" => [nil, 1, 1]}},
                                     command_name: "result1", contexts: map)
      store_result(mapped, path: single_path)

      merged = described_class.merge_results(single_path)

      expect(merged.contexts.covering(source_fixture("sample.rb"), 2)).to eq(["spec/a_spec.rb:1"])
    end

    it "answers nil when the timeout leaves nothing to merge" do
      store_result(outdated(first_result), path: single_path)

      merged = nil
      capture_stderr { merged = described_class.merge_results(single_path) }

      expect(merged).to be_nil
    end
  end

  describe ".store_result" do
    it "refreshes the resultset" do
      set = described_class.read_resultset
      described_class.store_result({})
      new_set = described_class.read_resultset
      expect(new_set).not_to be(set)
    end

    it "persists to disk" do
      entry = {"timestamp" => Time.now.to_f, "coverage" => {}}
      described_class.store_result("a" => entry)

      new_set = described_class.read_resultset
      expect(new_set).to eq("a" => entry)
    end

    it "synchronizes writes" do
      allow(described_class).to receive(:synchronize_resultset)
      described_class.store_result({})
      expect(described_class).to have_received(:synchronize_resultset)
    end

    it "answers true" do
      expect(described_class.store_result(first_result)).to be true
    end

    it "reads, merges and writes under a single lock" do
      events = []
      store = SimpleCov::ResultMerger::ResultsetStore
      allow(store).to receive(:with_flock).and_wrap_original do |original, &block|
        events << :locked
        original.call(&block)
        events << :unlocked
      end
      allow(store).to receive(:write).and_wrap_original do |original, resultset|
        events << :wrote
        original.call(resultset)
      end

      described_class.store_result(first_result)

      expect(events).to eq(%i[locked wrote unlocked])
    end

    describe "per-test maps across the merge" do
      def store_mapped_result(command_name, test_id, bitmap)
        map = SimpleCov::ContextMap.new
        map.record(test_id, source_fixture("sample.rb") => bitmap)
        described_class.store_result(
          SimpleCov::Result.new(
            {source_fixture("sample.rb") => {"lines" => [nil, 1, 1]}},
            command_name: command_name, contexts: map
          )
        )
      end

      def store_unmapped_result(command_name)
        described_class.store_result(
          SimpleCov::Result.new(
            {source_fixture("sample.rb") => {"lines" => [nil, 1, 1]}},
            command_name: command_name
          )
        )
      end

      it "unions the maps when every merged entry carries one" do
        store_mapped_result("RSpec", "spec/a_spec.rb:1", 0b10)
        store_mapped_result("Cucumber", "features/b.feature:4", 0b100)

        merged = described_class.merged_result

        expect(merged.contexts.covering(source_fixture("sample.rb"), 2)).to eq(["spec/a_spec.rb:1"])
        expect(merged.contexts.covering(source_fixture("sample.rb"), 3)).to eq(["features/b.feature:4"])
      end

      it "drops the map out loud when only some entries carry one" do
        store_mapped_result("RSpec", "spec/a_spec.rb:1", 0b10)
        store_unmapped_result("Cucumber")

        merged = nil
        output = capture_stderr { merged = described_class.merged_result }

        expect(merged.contexts).to be_nil
        expect(output).to include("Dropped the per-test map")
      end

      it "carries the union through merge_results, the collate path" do
        store_mapped_result("RSpec", "spec/a_spec.rb:1", 0b10)

        merged = described_class.merge_results(described_class.resultset_path, ignore_timeout: true)

        expect(merged.contexts.covering(source_fixture("sample.rb"), 2)).to eq(["spec/a_spec.rb:1"])
      end
    end

    describe "merging same-command-name entries written by a concurrent runner" do
      let(:process_start) { Time.now }
      let(:subprocess_result) do
        SimpleCov::Result.new(
          {source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}},
          command_name: "RSpec"
        )
      end
      let(:parent_empty_result) { SimpleCov::Result.new({}, command_name: "RSpec") }

      before { allow(SimpleCov).to receive(:process_start_time).and_return(process_start) }

      it "merges parent's incoming entry into the subprocess's when newer than our process_start_time" do
        subprocess_result.created_at = process_start + 1
        described_class.store_result(subprocess_result)

        parent_empty_result.created_at = process_start + 2
        described_class.store_result(parent_empty_result)

        merged = described_class.read_resultset.fetch("RSpec").fetch("coverage")
        expect(merged.keys).to contain_exactly(source_fixture("sample.rb"))
      end

      it "unions the tracked paths both entries recorded" do
        subprocess = SimpleCov::Result.new(
          {source_fixture("sample.rb") => {"lines" => [nil, 1]}},
          command_name: "RSpec", tracked_files: ["/x/one.rb", "/x/shared.rb"]
        )
        subprocess.created_at = process_start + 1
        described_class.store_result(subprocess)

        parent = SimpleCov::Result.new({}, command_name: "RSpec",
                                           tracked_files: ["/x/shared.rb", "/x/two.rb"])
        parent.created_at = process_start + 2
        described_class.store_result(parent)

        tracked = described_class.read_resultset.fetch("RSpec").fetch("tracked_files")
        expect(tracked).to contain_exactly("/x/one.rb", "/x/shared.rb", "/x/two.rb")
      end

      it "unions the test maps both entries recorded" do
        subprocess_map = SimpleCov::ContextMap.new
        subprocess_map.record("test/a_test.rb:3", source_fixture("sample.rb") => 0b1)
        subprocess = SimpleCov::Result.new(
          {source_fixture("sample.rb") => {"lines" => [1, 1]}},
          command_name: "RSpec", contexts: subprocess_map
        )
        subprocess.created_at = process_start + 1
        described_class.store_result(subprocess)

        parent = SimpleCov::Result.new({}, command_name: "RSpec", contexts: SimpleCov::ContextMap.new)
        parent.created_at = process_start + 2
        described_class.store_result(parent)

        stored = described_class.read_resultset.fetch("RSpec").fetch("contexts")
        expect(SimpleCov::ContextMap.from_hash(stored).covering(source_fixture("sample.rb"), 1))
          .to eq(["test/a_test.rb:3"])
      end

      it "drops the test map when only one of the concurrent entries recorded one" do
        subprocess_map = SimpleCov::ContextMap.new
        subprocess_map.record("test/a_test.rb:3", source_fixture("sample.rb") => 0b1)
        subprocess = SimpleCov::Result.new(
          {source_fixture("sample.rb") => {"lines" => [1, 1]}},
          command_name: "RSpec", contexts: subprocess_map
        )
        subprocess.created_at = process_start + 1
        described_class.store_result(subprocess)

        parent_empty_result.created_at = process_start + 2
        described_class.store_result(parent_empty_result)

        expect(described_class.read_resultset.fetch("RSpec")).not_to have_key("contexts")
      end

      it "still overwrites an older entry from a previous run (older than process_start)" do
        stale = SimpleCov::Result.new(
          {source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}},
          command_name: "RSpec"
        )
        stale.created_at = process_start - 60
        described_class.store_result(stale)

        parent_empty_result.created_at = process_start + 1
        described_class.store_result(parent_empty_result)

        expect(described_class.read_resultset.fetch("RSpec").fetch("coverage")).to be_empty
      end

      it "merges same-command entries carrying the same run identity" do
        subprocess = SimpleCov::Result.new(
          {source_fixture("sample.rb") => {"lines" => [nil, 1]}},
          command_name: "RSpec", run_id: "same-run", worker_id: "1"
        )
        subprocess.created_at = process_start - 60
        described_class.store_result(subprocess)

        parent = SimpleCov::Result.new({}, command_name: "RSpec", run_id: "same-run", worker_id: "1")
        described_class.store_result(parent)

        merged = described_class.read_resultset.fetch("RSpec").fetch("coverage")
        expect(merged).to have_key(source_fixture("sample.rb"))
      end

      it "merges a later entry written by an exec'd subprocess with its own run identity" do
        subprocess = SimpleCov::Result.new(
          {source_fixture("sample.rb") => {"lines" => [nil, 1]}},
          command_name: "RSpec", run_id: "child-run", worker_id: "1"
        )
        subprocess.created_at = process_start + 1
        described_class.store_result(subprocess)

        parent = SimpleCov::Result.new({}, command_name: "RSpec", run_id: "parent-run", worker_id: "1")
        parent.created_at = process_start + 2
        described_class.store_result(parent)

        merged = described_class.read_resultset.fetch("RSpec").fetch("coverage")
        expect(merged).to have_key(source_fixture("sample.rb"))
      end

      it "overwrites a same-second entry carrying a different run identity" do
        stale = SimpleCov::Result.new(
          {source_fixture("sample.rb") => {"lines" => [nil, 1]}},
          command_name: "RSpec", run_id: "old-run", worker_id: "1"
        )
        stale.created_at = process_start
        described_class.store_result(stale)

        current = SimpleCov::Result.new({}, command_name: "RSpec", run_id: "new-run", worker_id: "1")
        current.created_at = process_start
        described_class.store_result(current)

        expect(described_class.read_resultset.fetch("RSpec").fetch("coverage")).to be_empty
      end

      it "does not merge a legacy entry from earlier in the same second" do
        allow(SimpleCov).to receive(:process_start_time).and_return(Time.at(100.9))
        stale = SimpleCov::Result.new(
          {source_fixture("sample.rb") => {"lines" => [nil, 1]}}, command_name: "RSpec"
        )
        stale.created_at = Time.at(100)
        described_class.store_result(stale)

        current = SimpleCov::Result.new({}, command_name: "RSpec")
        current.created_at = Time.at(101)
        described_class.store_result(current)

        expect(described_class.read_resultset.fetch("RSpec").fetch("coverage")).to be_empty
      end

      it "is a no-op when process_start_time is unset (e.g. SimpleCov.start was never called)" do
        allow(SimpleCov).to receive(:process_start_time).and_return(nil)

        subprocess_result.created_at = Time.now
        described_class.store_result(subprocess_result)
        described_class.store_result(parent_empty_result)

        expect(described_class.read_resultset.fetch("RSpec").fetch("coverage")).to be_empty
      end
    end
  end

  describe ".resultset" do
    it "synchronizes reads" do
      allow(described_class).to receive(:synchronize_resultset)
      described_class.read_resultset
      expect(described_class).to have_received(:synchronize_resultset)
    end
  end

  describe ".synchronize_resultset" do
    let(:resultset_store) { SimpleCov::ResultMerger::ResultsetStore }

    it "creates the coverage directory before taking the lock" do
      FileUtils.rm_rf(SimpleCov.coverage_path)

      described_class.synchronize_resultset { :locked }

      expect(Dir.exist?(SimpleCov.coverage_path)).to be true
    end

    it "takes the file lock once across nested and sibling calls" do
      allow(resultset_store).to receive(:with_flock).and_call_original

      expect do
        Timeout.timeout(1) do
          described_class.synchronize_resultset do
            described_class.synchronize_resultset { :first }
            described_class.synchronize_resultset { :second }
          end
        end
      end.not_to raise_error

      expect(resultset_store).to have_received(:with_flock).once
    end

    it "blocks sibling threads until the owner releases the lock" do # rubocop:disable RSpec/ExampleLength
      entered = Queue.new
      release = Queue.new
      second_started = Queue.new
      first = Thread.new do
        described_class.synchronize_resultset do
          entered << :first
          release.pop
        end
      end
      expect(Timeout.timeout(1) { entered.pop }).to eq(:first)

      second = Thread.new do
        second_started << true
        described_class.synchronize_resultset { entered << :second }
      end
      Timeout.timeout(1) { second_started.pop }

      expect { Timeout.timeout(0.1) { entered.pop } }.to raise_error(Timeout::Error)
      release << true
      expect(Timeout.timeout(1) { entered.pop }).to eq(:second)
      first.value
      second.value
    ensure
      release << true if first&.alive?
      first&.join(1)
      second&.join(1)
    end

    it "releases both locks when the critical section raises" do
      expect do
        described_class.synchronize_resultset { raise "failure" }
      end.to raise_error("failure")

      acquired = Thread.new { described_class.synchronize_resultset { :acquired } }
      expect(Timeout.timeout(1) { acquired.value }).to eq(:acquired)
    end

    it "blocks other processes" do # rubocop:disable RSpec/ExampleLength
      skip "POSIX shell redirection and cross-process flock semantics are Unix-only" if Gem.win_platform?

      file = Tempfile.new("foo")

      test_script = <<-CODE
      require "simplecov"
      SimpleCov.coverage_dir(#{SimpleCov.coverage_dir.inspect})

      $stdout.sync = true
      puts "ready"
      $stdin.gets
      puts "attempting"

      SimpleCov::ResultMerger.synchronize_resultset do
        File.open(#{file.path.inspect}, "a") { |f| f.write("process 2\n") }
        puts "acquired"
      end
      CODE

      IO.popen([RbConfig.ruby, "-Ilib", "-e", test_script], "r+") do |other_process|
        expect(Timeout.timeout(30) { other_process.gets }).to eq("ready\n")

        described_class.synchronize_resultset do
          other_process.puts("start")
          other_process.flush
          expect(Timeout.timeout(10) { other_process.gets }).to eq("attempting\n")
          expect(other_process.wait_readable(0.1)).to be_nil

          File.open(file.path, "a") { |f| f.write("process 1\n") }
        end

        expect(Timeout.timeout(10) { other_process.gets }).to eq("acquired\n")
      end

      expect(file.read).to eq("process 1\nprocess 2\n")
    end
  end

private

  def store_result(result, path:)
    File.open(path, "w+") { |f| f.puts JSON.pretty_generate(result.to_hash) }
  end

  def outdated(result)
    result.created_at = Time.now - 172_800
    result
  end

  def expect_resultset_1_and_2_merged(result_hash)
    merged_coverage = result_hash.fetch("result1, result2").fetch("coverage")
    expect(merged_coverage).to eq(merged_resultsets)
  end
  describe "the write lock" do
    let(:store) { SimpleCov::ResultMerger::ResultsetStore }
    let(:tmp) { Dir.mktmpdir("simplecov-writelock-spec-") }
    let(:lock_path) { File.join(tmp, ".resultset.json.lock") }

    before { allow(store).to receive(:writelock_path).and_return(lock_path) }

    after { FileUtils.remove_entry(tmp) }

    it "holds an exclusive flock while the block runs, against readers and writers alike" do
      store.send(:holding_writelock) do
        File.open(lock_path) do |probe|
          expect(probe.flock(File::LOCK_EX | File::LOCK_NB)).to be(false)
          expect(probe.flock(File::LOCK_SH | File::LOCK_NB)).to be(false)
        end
      end
    end

    it "answers what the block answers and lets the lock go afterwards" do
      expect(store.send(:holding_writelock) { :written }).to be(:written)

      File.open(lock_path) do |probe|
        expect(probe.flock(File::LOCK_EX | File::LOCK_NB)).to be(0)
      end
    end

    it "opens the lock path as a file even when it starts with a pipe" do
      skip "a pipe is not a legal filename character on Windows" if Gem.win_platform?

      allow(store).to receive(:writelock_path).and_return("|true")

      Dir.chdir(tmp) { store.send(:holding_writelock) { nil } }

      expect(File).to exist(File.join(tmp, "|true"))
    end
  end
end
