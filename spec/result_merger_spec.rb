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
