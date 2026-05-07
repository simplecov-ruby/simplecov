# frozen_string_literal: true

require "helper"
require "coverage"

describe SimpleCov do
  describe ".result" do
    before do
      described_class.clear_result
      allow(Coverage).to receive(:result).once.and_return({})
    end

    context "with merging disabled" do
      before do
        allow(described_class).to receive(:use_merging).once.and_return(false)
        allow(described_class).to receive(:wait_for_other_processes)
      end

      context "when not running" do
        before do
          allow(Coverage).to receive(:running?).and_return(false)
        end

        it "returns nil" do
          expect(described_class.result).to be_nil
        end

        it "does not wait for other processes" do
          described_class.result
          expect(described_class).not_to have_received(:wait_for_other_processes)
        end
      end

      context "when running" do
        before do
          allow(Coverage).to receive(:running?).and_return(true)
        end

        it "uses the result from Coverage" do
          allow(Coverage).to receive(:result).and_return(__FILE__ => [0, 1])
          expect(described_class.result.filenames).to eq [__FILE__]
          expect(Coverage).to have_received(:result).once
        end

        it "adds not-loaded-files" do
          allow(described_class).to receive(:add_not_loaded_files).and_return([{}, Set.new])
          described_class.result
          expect(described_class).to have_received(:add_not_loaded_files).once
        end

        it "doesn't store the current coverage" do
          allow(SimpleCov::ResultMerger).to receive(:store_result)
          described_class.result
          expect(SimpleCov::ResultMerger).not_to have_received(:store_result)
        end

        it "doesn't merge the result" do
          allow(SimpleCov::ResultMerger).to receive(:merged_result)
          described_class.result
          expect(SimpleCov::ResultMerger).not_to have_received(:merged_result)
        end

        it "caches its result" do
          result = described_class.result
          expect(described_class.result).to be(result)
        end

        it "does not wait for other processes" do
          described_class.result
          expect(described_class).not_to have_received(:wait_for_other_processes)
        end
      end
    end

    context "with merging enabled" do
      let(:the_merged_result) { double }

      before do
        allow(described_class).to receive(:use_merging).once.and_return(true)
        allow(SimpleCov::ResultMerger).to receive(:store_result).once
        allow(SimpleCov::ResultMerger).to receive(:merged_result).once.and_return(the_merged_result)
        allow(described_class).to receive(:wait_for_other_processes)
      end

      context "when not running" do
        before do
          allow(Coverage).to receive(:running?).and_return(false)
        end

        it "merges the result" do
          expect(described_class.result).to be(the_merged_result)
        end

        it "waits for other processes" do
          described_class.result
          expect(described_class).to have_received(:wait_for_other_processes)
        end
      end

      context "when running" do
        before do
          allow(Coverage).to receive(:running?).and_return(true)
        end

        it "uses the result from Coverage" do
          allow(Coverage).to receive(:result).and_return({})
          described_class.result
          expect(Coverage).to have_received(:result).once
        end

        it "adds not-loaded-files" do
          allow(described_class).to receive(:add_not_loaded_files).and_return([{}, Set.new])
          described_class.result
          expect(described_class).to have_received(:add_not_loaded_files).once
        end

        it "stores the current coverage" do
          allow(SimpleCov::ResultMerger).to receive(:store_result)
          described_class.result
          expect(SimpleCov::ResultMerger).to have_received(:store_result).once
        end

        it "merges the result" do
          expect(described_class.result).to be(the_merged_result)
        end

        it "caches its result" do
          result = described_class.result
          expect(described_class.result).to be(result)
        end

        it "waits for other processes" do
          described_class.result
          expect(described_class).to have_received(:wait_for_other_processes)
        end
      end
    end
  end

  describe ".exit_status_from_exception" do
    context "when no exception has occurred" do
      it "returns nil" do
        expect(described_class.exit_status_from_exception).to be_nil
      end
    end

    context "when a SystemExit has occurred" do
      it "returns the SystemExit status" do
        raise SystemExit, 1
      rescue SystemExit
        expect(described_class.exit_status_from_exception).to eq(1)
      end
    end

    context "when a non SystemExit occurs" do
      it "return SimpleCov::ExitCodes::EXCEPTION" do
        raise "no system exit"
      rescue StandardError
        expect(described_class.exit_status_from_exception).to eq(SimpleCov::ExitCodes::EXCEPTION)
      end
    end
  end

  describe ".process_result" do
    let(:result) { SimpleCov::Result.new({}) }

    context "when minimum coverage is 100%" do
      before do
        allow(described_class).to receive_messages(minimum_coverage: {line: 100}, result?: true)
      end

      context "when actual coverage is almost 100%" do
        before do
          line_stats = instance_double(SimpleCov::CoverageStatistics, percent: 100 * 32_847.0 / 32_848)
          allow(result).to receive(:coverage_statistics).and_return(line: line_stats)
        end

        it "return SimpleCov::ExitCodes::MINIMUM_COVERAGE" do
          expect(
            described_class.process_result(result)
          ).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
        end
      end

      context "when actual coverage is exactly 100%" do
        before do
          line_stats = instance_double(SimpleCov::CoverageStatistics, percent: 100.0)
          allow(result).to receive_messages(
            covered_percent: 100.0,
            coverage_statistics: {line: line_stats},
            covered_percentages: []
          )
          allow(SimpleCov::LastRun).to receive(:read).and_return(nil)
        end

        it "return SimpleCov::ExitCodes::SUCCESS" do
          expect(
            described_class.process_result(result)
          ).to eq(SimpleCov::ExitCodes::SUCCESS)
        end
      end

      context "when branch coverage" do
        before do
          allow(described_class).to receive_messages(minimum_coverage: {branch: 90}, result?: true)
        end

        it "errors out when the coverage is too low" do
          branch_stats = instance_double(SimpleCov::CoverageStatistics, percent: 89.99)
          allow(result).to receive(:coverage_statistics).and_return(branch: branch_stats)

          expect(
            described_class.process_result(result)
          ).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
        end
      end
    end
  end

  describe ".collate" do
    let(:first_resultset) do
      {source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}}
    end

    let(:second_resultset) do
      {source_fixture("sample.rb") => {"lines" => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]}}
    end

    let(:resultset_path) { SimpleCov::ResultMerger.resultset_path }

    let(:resultset_folder) { File.dirname(resultset_path) }

    let(:merged_result) do
      {
        "result1, result2" => {
          "coverage" => {
            source_fixture("sample.rb") => {
              "lines" => [1, 1, 2, 2, nil, nil, 2, 2, nil, nil]
            }
          }
        }
      }
    end

    let(:collated) do
      JSON.parse(File.read(resultset_path)).transform_values { |v| v.reject { |k| k == "timestamp" } }
    end

    context "when no files to be merged" do
      it "shows an error message" do
        expect do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          described_class.collate glob
        end.to raise_error("There are no reports to be merged")
      end
    end

    context "when files to be merged" do
      before do
        allow(described_class).to receive(:run_exit_tasks!)
      end

      context "when a single report to be merged" do
        before do
          create_mergeable_report("result1", first_resultset)
        end

        after do
          clear_mergeable_reports
        end

        it "creates a merged report identical to the original" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          described_class.collate glob

          expected = {"result1" => {"coverage" => first_resultset}}
          expect(collated).to eq(expected)
          expect(described_class).to have_received(:run_exit_tasks!)
        end
      end

      context "when multiple reports to be merged" do
        before do
          create_mergeable_report("result1", first_resultset)
          create_mergeable_report("result2", second_resultset)
        end

        after do
          clear_mergeable_reports
        end

        it "creates a merged report" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          described_class.collate glob

          expect(collated).to eq(merged_result)
          expect(described_class).to have_received(:run_exit_tasks!)
        end
      end

      context "when multiple reports to be merged, one of them outdated" do
        before do
          create_mergeable_report("result1", first_resultset)
          create_mergeable_report("result2", second_resultset, outdated: true)
        end

        after do
          clear_mergeable_reports
        end

        it "ignores timeout by default creating a report with all values" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          described_class.collate glob

          expect(collated).to eq(merged_result)
          expect(described_class).to have_received(:run_exit_tasks!)
        end

        it "creates a merged report with only the results from the current resultset if ignore_timeout: false" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          described_class.collate glob, ignore_timeout: false

          expected = {"result1" => {"coverage" => first_resultset}}
          expect(collated).to eq(expected)
          expect(described_class).to have_received(:run_exit_tasks!)
        end
      end

    private

      def create_mergeable_report(name, resultset, outdated: false)
        result = SimpleCov::Result.new(resultset)
        result.command_name = name
        result.created_at = Time.now - 172_800 if outdated
        SimpleCov::ResultMerger.store_result(result)
        FileUtils.mv resultset_path, "#{resultset_path}#{name}.final"
      end

      def clear_mergeable_reports
        SimpleCov.clear_result
        FileUtils.rm Dir.glob("#{resultset_path}*")
      end

      def expect_merged
        merged_lines = [1, 1, 2, 2, nil, nil, 2, 2, nil, nil]
        expected = {
          "result1, result2" => {
            "coverage" => {source_fixture("sample.rb") => {"lines" => merged_lines}}
          }
        }
        expect(collated).to eq(expected)
      end
    end
  end

  # Normally wouldn't test private methods but just start has side effects that
  # cause errors so for time this is pragmatic (tm)
  describe ".start_coverage_measurement" do
    after do
      # SimpleCov is a Singleton/global object so once any test enables
      # any kind of coverage data it stays there.
      # Hence, we use clear_coverage_data to create a "clean slate" for these tests
      described_class.clear_coverage_criteria
    end

    before do
      # `start_coverage_with_criteria` short-circuits with `unless
      # Coverage.running?`. These tests verify the kwargs handed to
      # Coverage.start, which only fire when Coverage isn't already
      # running — so stub the running check to false. (Without this,
      # the test would fail when run with the dogfood bootstrap, which
      # starts Coverage before requiring simplecov.)
      allow(Coverage).to receive(:running?).and_return(false)
    end

    it "starts coverage in lines mode by default" do
      allow(Coverage).to receive(:start)

      described_class.send :start_coverage_measurement

      expect(Coverage).to have_received(:start).with({lines: true})
    end

    it "starts coverage with lines and branches if branches is activated" do
      allow(Coverage).to receive(:start)
      described_class.enable_coverage :branch

      described_class.send :start_coverage_measurement

      expect(Coverage).to have_received(:start).with({lines: true, branches: true})
    end

    it "starts coverage with lines and methods if method coverage is activated" do
      allow(Coverage).to receive(:start)
      described_class.enable_coverage :method

      described_class.send :start_coverage_measurement

      expect(Coverage).to have_received(:start).with({lines: true, methods: true})
    end
  end
end
