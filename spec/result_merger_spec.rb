# frozen_string_literal: true

require "helper"
require "tempfile"
require "timeout"

describe SimpleCov::ResultMerger do
  after do
    File.delete(SimpleCov::ResultMerger.resultset_path) if File.exist?(SimpleCov::ResultMerger.resultset_path)
  end

  let(:resultset1) do
    {
      source_fixture("sample.rb") => {lines: [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]},
      source_fixture("app/models/user.rb") => {lines: [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]},
      source_fixture("app/controllers/sample_controller.rb") => {lines: [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]},
      source_fixture("resultset1.rb") => {lines: [1, 1, 1, 1]},
      source_fixture("parallel_tests.rb") => {lines: [nil, 0, nil, 0]},
      source_fixture("conditionally_loaded_1.rb") => {lines: [nil, 0, 1]} # loaded only in the first resultset
    }
  end

  let(:resultset2) do
    {
      source_fixture("sample.rb") => {lines: [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]},
      source_fixture("app/models/user.rb") => {lines: [nil, 1, 5, 1, nil, nil, 1, 0, nil, nil]},
      source_fixture("app/controllers/sample_controller.rb") => {lines: [nil, 3, 1, nil, nil, nil, 1, 0, nil, nil]},
      source_fixture("resultset2.rb") => {lines: [nil, 1, 1, nil]},
      source_fixture("parallel_tests.rb") => {lines: [nil, nil, 0, 0]},
      source_fixture("conditionally_loaded_2.rb") => {lines: [nil, 0, 1]} # loaded only in the second resultset
    }
  end

  let(:merged_resultset1_and2) do
    {
      source_fixture("sample.rb") => {lines: [1, 1, 2, 2, nil, nil, 2, 2, nil, nil]},
      source_fixture("app/models/user.rb") => {lines: [nil, 2, 6, 2, nil, nil, 2, 0, nil, nil]},
      source_fixture("app/controllers/sample_controller.rb") => {lines: [nil, 4, 2, 1, nil, nil, 2, 0, nil, nil]},
      source_fixture("resultset1.rb") => {lines: [1, 1, 1, 1]},
      source_fixture("parallel_tests.rb") => {lines: [nil, nil, nil, 0]},
      source_fixture("conditionally_loaded_1.rb") => {lines: [nil, 0, 1]},
      source_fixture("resultset2.rb") => {lines: [nil, 1, 1, nil]},
      source_fixture("conditionally_loaded_2.rb") => {lines: [nil, 0, 1]}
    }
  end

  let(:result1) { SimpleCov::Result.new(resultset1, command_name: "result1") }
  let(:result2) { SimpleCov::Result.new(resultset2, command_name: "result2") }

  describe "resultset handling" do
    # See GitHub issue #6
    it "returns an empty hash when the resultset cache file is empty" do
      File.open(SimpleCov::ResultMerger.resultset_path, "w+") { |f| f.puts "" }
      expect(SimpleCov::ResultMerger.read_resultset).to be_empty
    end

    # See GitHub issue #6
    it "returns an empty hash when the resultset cache file is not present" do
      system "rm #{SimpleCov::ResultMerger.resultset_path}" if File.exist?(SimpleCov::ResultMerger.resultset_path)
      expect(SimpleCov::ResultMerger.read_resultset).to be_empty
    end
  end

  describe "basic workings with 2 resultsets" do
    before do
      system "rm #{SimpleCov::ResultMerger.resultset_path}" if File.exist?(SimpleCov::ResultMerger.resultset_path)
      SimpleCov::ResultMerger.store_result(result1)
      SimpleCov::ResultMerger.store_result(result2)
    end

    it "has stored data in resultset_path JSON file" do
      expect(File.readlines(SimpleCov::ResultMerger.resultset_path).length).to be > 50
    end

    it "returns a hash containing keys ['result1' and 'result2'] for resultset" do
      expect(SimpleCov::ResultMerger.read_resultset.keys.sort).to eq %w[result1 result2]
    end

    it "returns proper values for merged_result" do
      result = SimpleCov::ResultMerger.merged_result

      expect_resultset_1_and_2_merged(result.to_hash)
    end

    context "with second result way above the merge_timeout" do
      let(:result2) { outdated(super()) }

      before do
        SimpleCov::ResultMerger.store_result(result2)
      end

      it "has only one result in SimpleCov::ResultMerger.results" do
        # second result does not appear in the merged results
        merged_coverage = SimpleCov::ResultMerger.merged_result

        expect(merged_coverage.command_name).to eq "result1"
        expect(merged_coverage.original_result).to eq resultset1
      end
    end
  end

  describe ".merge_and_store" do
    let(:resultset_prefix) { "test_resultset" }
    let(:resultset1_path) { "#{resultset_prefix}1.json" }
    let(:resultset2_path) { "#{resultset_prefix}2.json" }

    describe "merging behavior" do
      before :each do
        store_result(result1, path: resultset1_path)
        store_result(result2, path: resultset2_path)
      end

      after :each do
        FileUtils.rm Dir.glob("#{resultset_prefix}*.json")
      end

      context "2 normal results" do
        it "correctly merges the 2 results" do
          result = SimpleCov::ResultMerger.merge_and_store(resultset1_path, resultset2_path)
          expect_resultset_1_and_2_merged(result.to_hash)
        end

        it "has the result stored" do
          SimpleCov::ResultMerger.merge_and_store(resultset1_path, resultset2_path)

          expect_resultset_1_and_2_merged(SimpleCov::ResultMerger.merged_result.to_hash)
        end
      end

      context "1 resultset is outdated" do
        let(:result1) { outdated(super()) }

        it "completely omits the result from the merge" do
          result_hash = SimpleCov::ResultMerger.merge_and_store(resultset1_path, resultset2_path).to_hash

          expect(result_hash.keys).to eq ["result2"]

          merged_coverage = result_hash.fetch("result2").fetch("coverage")
          expect(merged_coverage).to eq(resultset2)
        end

        it "includes it when we say ignore_timeout: true" do
          result_hash = SimpleCov::ResultMerger.merge_and_store(resultset1_path, resultset2_path, ignore_timeout: true).to_hash

          expect_resultset_1_and_2_merged(result_hash)
        end
      end

      context "both resultsets outdated" do
        let(:result1) { outdated(super()) }
        let(:result2) { outdated(super()) }

        it "completely omits the result from the merge" do
          allow(SimpleCov::ResultMerger).to receive(:store)

          result = SimpleCov::ResultMerger.merge_and_store(resultset1_path, resultset2_path)

          expect(result).to eq nil
          expect(SimpleCov::ResultMerger).not_to have_received(:store)
        end

        it "includes both when we say ignore_timeout: true" do
          result_hash = SimpleCov::ResultMerger.merge_and_store(resultset1_path, resultset2_path, ignore_timeout: true).to_hash

          expect_resultset_1_and_2_merged(result_hash)
        end
      end

      describe "method coverage", if: SimpleCov.method_coverage_supported? do
        before do
          SimpleCov.enable_coverage :method
          store_result(result3, path: resultset3_path)
        end

        after do
          SimpleCov.clear_coverage_criteria
        end

        let(:resultset1) do
          {
            source_fixture("methods.rb") => {
              methods: {
                ["A", :method1, 2, 2, 5, 5] => 1,
                ["A", :method2, 9, 2, 11, 5] => 0,
                ["A", :method3, 13, 2, 15, 5] => 0
              }
            }
          }
        end

        let(:resultset2) do
          {
            source_fixture("methods.rb") => {
              methods: {
                ["A", :method1, 2, 2, 5, 5] => 0,
                ["A", :method2, 9, 2, 11, 5] => 1,
                ["A", :method3, 13, 2, 15, 5] => 0
              }
            }
          }
        end

        let(:resultset3) do
          {
            source_fixture("methods.rb") => {
              methods: {
                ["B", :method1, 2, 2, 5, 5] => 1,
                ["B", :method2, 9, 2, 11, 5] => 0,
                ["B", :method3, 13, 2, 15, 5] => 0
              }
            }
          }
        end

        let(:result3) { SimpleCov::Result.new(resultset3, command_name: "result3") }
        let(:resultset3_path) { "#{resultset_prefix}3.json" }

        it "correctly merges the 3 results" do
          result = SimpleCov::ResultMerger.merge_and_store(
            resultset1_path, resultset2_path, resultset3_path
          )

          merged_coverage = result.original_result.fetch(source_fixture("methods.rb"))

          expect(merged_coverage.fetch(:methods)).to eq(
            ["A", :method1, 2, 2, 5, 5] => 1,
            ["A", :method2, 9, 2, 11, 5] => 1,
            ["A", :method3, 13, 2, 15, 5] => 0,
            ["B", :method1, 2, 2, 5, 5] => 1,
            ["B", :method2, 9, 2, 11, 5] => 0,
            ["B", :method3, 13, 2, 15, 5] => 0
          )
        end
      end
    end

    context "pre 0.18 result format" do
      let(:file_path) { "old_resultset.json" }
      let(:content) { {source_fixture("three.rb") => [nil, 1, 2]} }

      before :each do
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

      after :each do
        FileUtils.rm file_path
      end

      it "gets the same content back but under \"lines\"" do
        result = SimpleCov::ResultMerger.merge_and_store(file_path)

        expect(result.original_result).to eq(
          source_fixture("three.rb") => {lines: [nil, 1, 2]}
        )
      end
    end
  end

  describe ".store_result" do
    it "refreshes the resultset" do
      set = SimpleCov::ResultMerger.read_resultset
      SimpleCov::ResultMerger.store_result({})
      new_set = SimpleCov::ResultMerger.read_resultset
      expect(new_set).not_to be(set)
    end

    it "persists to disk" do
      SimpleCov::ResultMerger.store_result("a" => [1])

      new_set = SimpleCov::ResultMerger.read_resultset
      expect(new_set).to eq("a" => [1])
    end

    it "synchronizes writes" do
      expect(SimpleCov::ResultMerger).to receive(:synchronize_resultset)
      SimpleCov::ResultMerger.store_result({})
    end
  end

  describe ".resultset" do
    it "synchronizes reads" do
      expect(SimpleCov::ResultMerger).to receive(:synchronize_resultset)
      SimpleCov::ResultMerger.read_resultset
    end
  end

  describe ".synchronize_resultset" do
    it "is reentrant (i.e. doesn't block its own process)" do
      # without @resultset_locked, this spec would fail and
      # `.store_result` wouldn't work
      expect do
        Timeout.timeout(1) do
          SimpleCov::ResultMerger.synchronize_resultset do
            SimpleCov::ResultMerger.synchronize_resultset do
              # nothing
            end
          end
        end
      end.not_to raise_error
    end

    it "blocks other processes" do
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

      # rubocop:disable Security/Open
      other_process = open("|ruby -e #{Shellwords.escape(test_script)} 2>/dev/null")
      # rubocop:enable Security/Open

      SimpleCov::ResultMerger.synchronize_resultset do
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
    expect(merged_coverage).to eq(merged_resultset1_and2)
  end
end
