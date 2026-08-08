# frozen_string_literal: true

require "helper"
require "tempfile"
require "timeout"

RSpec.describe SimpleCov::ResultMerger do
  before do
    # Several examples write the resultset cache directly. SimpleCov.coverage_path
    # only creates the directory when called with an explicit path, so depending on
    # example order it may not exist yet — ensure it does before each example.
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
      source_fixture("conditionally_loaded_1.rb") => {"lines" => [nil, 0, 1]} # loaded only in the first resultset
    }
  end

  let(:second_resultset) do
    {
      source_fixture("sample.rb") => {"lines" => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]},
      source_fixture("app/models/user.rb") => {"lines" => [nil, 1, 5, 1, nil, nil, 1, 0, nil, nil]},
      source_fixture("app/controllers/sample_controller.rb") => {"lines" => [nil, 3, 1, nil, nil, nil, 1, 0, nil, nil]},
      source_fixture("resultset2.rb") => {"lines" => [nil, 1, 1, nil]},
      source_fixture("parallel_tests.rb") => {"lines" => [nil, nil, 0, 0]},
      source_fixture("conditionally_loaded_2.rb") => {"lines" => [nil, 0, 1]} # loaded only in the second resultset
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

  # The loaded/not-loaded distinction isn't serialized into `.resultset.json`,
  # so a merged result has to re-derive it from the merged line counts. Without
  # it every file in a merged report is `loaded: true`, and the #902 rule that
  # reports 0% rather than a misleading 100% for a never-loaded file with no
  # branch or method data can never fire on the merge path. See #1250.
  # Injection happens here rather than in each contributing process: only the
  # union of what they all loaded says what was really never loaded, and doing
  # it per process meant N workers simulated the same file up to N times. The
  # paths come from the resultsets, so a `collate` that never ran
  # `SimpleCov.start` still injects correctly. See #1250.
  # A simulated file has to have the same shape as the files it is merged
  # alongside. Taking the criteria from this process's configuration gets that
  # wrong when the merge did not measure anything itself, which is exactly the
  # `simplecov merge` case. Fewer tables than its neighbours is what inflates
  # the percentage #1059 fixed. See #1250.
  describe "the shape of an injected file" do
    # sample.rb has methods to synthesize; resultset1.rb is four `puts` lines.
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

    it "leaves them empty when the merged files carry none",
       if: SimpleCov::StaticCoverageExtractor.available? do
      allow(SimpleCov).to receive_messages(branch_coverage?: true, method_coverage?: true)

      entry = injected(loaded => {"lines" => [1, 1]})

      expect(entry["methods"]).to be_empty
    end

    # Nothing to be consistent with, so the configuration is all there is.
    it "falls back to this process's criteria when the merge carried no files" do
      allow(SimpleCov).to receive_messages(line_coverage?: false, branch_coverage?: true, method_coverage?: false)

      result = described_class.send(:create_result, ["merged"], {}, tracked_files: Set[never_loaded])

      expect(result.original_result.fetch(never_loaded)).not_to have_key("lines")
    end
  end

  # An expired entry's coverage is dropped, so its tracked paths have to go
  # with it. Otherwise a file only a stale run ever tracked is simulated into
  # the merged report at 0% while the run that tracked it contributes nothing.
  # See #1250.
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

    it "leaves a file some process loaded alone" do
      result = described_class.send(:create_result, ["merged"], coverage,
                                    tracked_files: Set[loaded, never_loaded])

      expect(result.original_result[loaded]).to eq(coverage[loaded])
      expect(result.files.find { |f| f.filename == loaded }).not_to be_not_loaded
    end

    it "injects nothing when the resultsets recorded no tracked files" do
      result = described_class.send(:create_result, ["merged"], coverage)

      expect(result.original_result.keys).to contain_exactly(loaded)
    end

    it "carries the tracked paths onto the merged result for a later collate" do
      result = described_class.send(:create_result, ["merged"], coverage,
                                    tracked_files: Set[loaded, never_loaded])

      expect(result.tracked_files).to contain_exactly(loaded, never_loaded)
      expect(result.to_hash["merged"]["tracked_files"]).to contain_exactly(loaded, never_loaded)
    end

    # Resultsets written before tracked paths were recorded already carry the
    # unloaded files their process injected, so re-injecting must not disturb
    # them. Injection skips whatever is already present, whoever put it there.
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

  describe "not-loaded files in a merged result" do
    subject(:result) { described_class.send(:create_result, ["merged"], coverage) }

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

    # A file whose lines are all zero but which has synthesized branch data
    # still reports through the normal statistics path; the #902 rule only
    # covers the case where there is no branch or method data at all.
    it "reports 0% rather than 100% for a never-loaded file with no branch data" do
      expect(file(never_executed).coverage_statistics[:branch]&.percent).to eq(0.0)
    end

    # A branch-only or method-only run reports no line data at all, so line
    # counts cannot say what was loaded. Judging on them anyway would mark
    # every file in the report not loaded and report 0% for branchless ones.
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

    # A loaded file need not have executed anything: a file with no
    # executable lines (comments and blanks throughout) reports every line
    # as nil. Only a relevant line can say a file was never executed, so
    # such a file must not be flagged — flagging it would turn its branch
    # and method coverage into #902's 0% even though it was really loaded.
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

    # `Combine` short-circuits to the non-nil side, so a file present in one
    # result without lines and absent from another merges to a nil lines value.
    context "when a merged entry has a nil lines value" do
      let(:coverage) { {executed => {"lines" => nil, "branches" => {}, "methods" => {}}} }

      it "does not flag it" do
        expect(file(executed)).not_to be_not_loaded
      end
    end
  end

  describe "resultset handling" do
    # See GitHub issue #6
    it "returns an empty hash when the resultset cache file is empty" do
      File.open(described_class.resultset_path, "w+") { |f| f.puts "" }
      expect(described_class.read_resultset).to be_empty
    end

    # See GitHub issue #6
    it "returns an empty hash when the resultset cache file is not present" do
      system "rm #{described_class.resultset_path}" if File.exist?(described_class.resultset_path)
      expect(described_class.read_resultset).to be_empty
    end

    it "warns and returns an empty hash when the resultset is malformed JSON" do
      File.write(described_class.resultset_path, "this is not json {")
      stderr = capture_stderr { expect(described_class.read_resultset).to be_empty }
      expect(stderr).to include("Parsing JSON content of resultset file failed")
    end
  end

  describe "basic workings with 2 resultsets" do
    before do
      system "rm #{described_class.resultset_path}" if File.exist?(described_class.resultset_path)
      described_class.store_result(first_result)
      described_class.store_result(second_result)
    end

    it "has stored data in resultset_path JSON file" do
      expect(File.readlines(described_class.resultset_path).length).to be > 50
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
        # second result does not appear in the merged results
        merged_coverage = described_class.merged_result

        expect(merged_coverage.command_name).to eq "result1"
        expect(merged_coverage.original_result).to eq first_resultset
      end
    end
  end

  describe ".merge_and_store" do
    let(:resultset_prefix) { "test_resultset" }
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

      # `merge_results` passes a block to collect the tracked paths each
      # resultset recorded, but `absorb_results` is public and the collate
      # benchmark calls it without one. See #1250.
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
          # Forked workers set `print_errors false` and merge the resultset
          # too; without this the expired-results warning is emitted once per
          # worker. See parallel (subprocess) merging.
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

        # After JSON round-trip, array keys become string representations.
        # The combiner merges by these string keys, summing counts.
        expect(methods.values.sort).to eq([1, 3])
      end
    end

    context "when pre 0.18 result format" do
      let(:file_path) { "old_resultset.json" }
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
    let(:resultset_prefix) { "fold_test_resultset" }
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
  end

  describe ".store_result" do
    it "refreshes the resultset" do
      set = described_class.read_resultset
      described_class.store_result({})
      new_set = described_class.read_resultset
      expect(new_set).not_to be(set)
    end

    it "persists to disk" do
      described_class.store_result("a" => [1])

      new_set = described_class.read_resultset
      expect(new_set).to eq("a" => [1])
    end

    it "synchronizes writes" do
      allow(described_class).to receive(:synchronize_resultset)
      described_class.store_result({})
      expect(described_class).to have_received(:synchronize_resultset)
    end

    # See https://github.com/simplecov-ruby/simplecov/issues/581. When a parent
    # process (Rakefile, Rails Bundler.require) shells out to the test runner,
    # the subprocess writes its real result to the resultset and then the
    # parent's at_exit hook stores its own (empty) result under the same
    # command_name. Without merging, the parent overwrites the subprocess's
    # data; with the guard, the parent's incoming entry is combined with the
    # existing one so the subprocess's coverage survives.
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
        subprocess_result.created_at = process_start + 1 # subprocess finished after we started
        described_class.store_result(subprocess_result)

        parent_empty_result.created_at = process_start + 2
        described_class.store_result(parent_empty_result)

        merged = described_class.read_resultset.fetch("RSpec").fetch("coverage")
        expect(merged.keys).to contain_exactly(source_fixture("sample.rb"))
      end

      # Concurrent workers sharing a command name may have been told to track
      # different sets, so the merged entry keeps both rather than letting the
      # later write win. See #1250.
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

      it "still overwrites an older entry from a previous run (older than process_start)" do
        # A stale entry from a previous test run shouldn't be merged in — it's
        # not from a concurrent runner, just leftover state.
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
    it "is reentrant (i.e. doesn't block its own process)" do
      # without @resultset_locked, this spec would fail and
      # `.store_result` wouldn't work
      expect do
        Timeout.timeout(1) do
          described_class.synchronize_resultset do
            described_class.synchronize_resultset do
              # nothing
            end
          end
        end
      end.not_to raise_error
    end

    it "stays reentrant across sibling nested calls" do
      # The first nested call must not reset the outer lock's flag on its
      # way out: the second sibling call would then take the flock path
      # and self-deadlock against the fd the outer call still holds.
      expect do
        Timeout.timeout(1) do
          described_class.synchronize_resultset do
            described_class.synchronize_resultset { :first }
            described_class.synchronize_resultset { :second }
          end
        end
      end.not_to raise_error
    end

    it "blocks other processes" do # rubocop:disable RSpec/ExampleLength
      skip "POSIX shell redirection and cross-process flock semantics are Unix-only" if Gem.win_platform?

      file = Tempfile.new("foo")

      test_script = <<-CODE
      require "simplecov"
      SimpleCov.coverage_dir(#{SimpleCov.coverage_dir.inspect})

      # ensure the parent process has enough time to get a
      # lock before we do
      sleep 0.5

      $stdout.sync = true
      puts "running" # see `sleep`s in parent process

      SimpleCov::ResultMerger.synchronize_resultset do
        File.open(#{file.path.inspect}, "a") { |f| f.write("process 2\n") }
      end
      CODE

      IO.popen("ruby -e #{Shellwords.escape(test_script)} 2>/dev/null") do |other_process|
        described_class.synchronize_resultset do
          # wait until the child process is going, and then wait some more
          # so we can be sure it blocks on the lock we already have.
          sleep 0.1 until other_process.gets == "running\n"
          sleep 1

          # despite the sleeps, this will be written first since we got
          # the first lock
          File.open(file.path, "a") { |f| f.write("process 1\n") }
        end

        # wait for it to finish
        other_process.gets
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
end
