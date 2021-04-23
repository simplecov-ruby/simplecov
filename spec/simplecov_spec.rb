# frozen_string_literal: true

require "helper"
require "coverage"

describe SimpleCov do
  describe ".result" do
    before do
      SimpleCov.clear_result
      allow(Coverage).to receive(:result).once.and_return({})
    end

    context "with merging disabled" do
      before do
        allow(SimpleCov).to receive(:use_merging).once.and_return(false)
        expect(SimpleCov).to_not receive(:wait_for_other_processes)
      end

      context "when not running" do
        before do
          allow(SimpleCov).to receive(:running).and_return(false)
        end

        it "returns nil" do
          expect(SimpleCov.result).to be_nil
        end
      end

      context "when running" do
        before do
          allow(SimpleCov).to receive(:running).and_return(true, false)
        end

        it "uses the result from Coverage" do
          expect(Coverage).to receive(:result).once.and_return(__FILE__ => [0, 1])
          expect(SimpleCov.result.filenames).to eq [__FILE__]
        end

        it "adds not-loaded-files" do
          expect(SimpleCov).to receive(:add_not_loaded_files).once.and_return({})
          SimpleCov.result
        end

        it "doesn't store the current coverage" do
          expect(SimpleCov::ResultMerger).not_to receive(:store_result)
          SimpleCov.result
        end

        it "doesn't merge the result" do
          expect(SimpleCov::ResultMerger).not_to receive(:merged_result)
          SimpleCov.result
        end

        it "caches its result" do
          result = SimpleCov.result
          expect(SimpleCov.result).to be(result)
        end
      end
    end

    context "with merging enabled" do
      let(:the_merged_result) { double }

      before do
        allow(SimpleCov).to receive(:use_merging).once.and_return(true)
        allow(SimpleCov::ResultMerger).to receive(:store_result).once
        allow(SimpleCov::ResultMerger).to receive(:merged_result).once.and_return(the_merged_result)
        expect(SimpleCov).to receive(:wait_for_other_processes)
      end

      context "when not running" do
        before do
          allow(SimpleCov).to receive(:running).and_return(false)
        end

        it "merges the result" do
          expect(SimpleCov.result).to be(the_merged_result)
        end
      end

      context "when running" do
        before do
          allow(SimpleCov).to receive(:running).and_return(true, false)
        end

        it "uses the result from Coverage" do
          expect(Coverage).to receive(:result).once.and_return({})
          SimpleCov.result
        end

        it "adds not-loaded-files" do
          expect(SimpleCov).to receive(:add_not_loaded_files).once.and_return({})
          SimpleCov.result
        end

        it "stores the current coverage" do
          expect(SimpleCov::ResultMerger).to receive(:store_result).once
          SimpleCov.result
        end

        it "merges the result" do
          expect(SimpleCov.result).to be(the_merged_result)
        end

        it "caches its result" do
          result = SimpleCov.result
          expect(SimpleCov.result).to be(result)
        end
      end
    end
  end

  describe ".exit_status_from_exception" do
    context "when no exception has occurred" do
      it "returns nil" do
        expect(SimpleCov.exit_status_from_exception).to eq(nil)
      end
    end

    context "when a SystemExit has occurred" do
      it "returns the SystemExit status" do
        raise SystemExit, 1
      rescue SystemExit
        expect(SimpleCov.exit_status_from_exception).to eq(1)
      end
    end

    context "when a non SystemExit occurs" do
      it "return SimpleCov::ExitCodes::EXCEPTION" do
        raise "no system exit"
      rescue StandardError
        expect(SimpleCov.exit_status_from_exception).to eq(SimpleCov::ExitCodes::EXCEPTION)
      end
    end
  end

  describe ".process_result" do
    let(:result) { SimpleCov::Result.new({}) }

    context "when minimum coverage is 100%" do
      before do
        allow(SimpleCov).to receive(:minimum_coverage).and_return(line: 100)
        allow(SimpleCov).to receive(:result?).and_return(true)
      end

      context "when actual coverage is almost 100%" do
        before do
          allow(result).to receive(:coverage_statistics).and_return(line: double("statistics", percent: 100 * 32_847.0 / 32_848))
        end

        it "return SimpleCov::ExitCodes::MINIMUM_COVERAGE" do
          expect(
            SimpleCov.process_result(result)
          ).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
        end
      end

      context "when actual coverage is exactly 100%" do
        before do
          allow(result).to receive(:covered_percent).and_return(100.0)
          allow(result).to receive(:coverage_statistics).and_return(
            line: double("statistics", percent: 100.0)
          )
          allow(result).to receive(:covered_percentages).and_return([])
          allow(SimpleCov::LastRun).to receive(:read).and_return(nil)
        end

        it "return SimpleCov::ExitCodes::SUCCESS" do
          expect(
            SimpleCov.process_result(result)
          ).to eq(SimpleCov::ExitCodes::SUCCESS)
        end
      end

      context "branch coverage" do
        before do
          allow(SimpleCov).to receive(:minimum_coverage).and_return(branch: 90)
          allow(SimpleCov).to receive(:result?).and_return(true)
        end

        it "errors out when the coverage is too low" do
          allow(result).to receive(:coverage_statistics).and_return(branch: double("statistics", percent: 89.99))

          expect(
            SimpleCov.process_result(result)
          ).to eq(SimpleCov::ExitCodes::MINIMUM_COVERAGE)
        end
      end
    end
  end

  describe ".collate" do
    let(:resultset1) do
      {source_fixture("sample.rb") => {lines: [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}}
    end

    let(:resultset2) do
      {source_fixture("sample.rb") => {lines: [1, nil, 1, 1, nil, nil, 1, 1, nil, nil]}}
    end

    let(:resultset_path) { SimpleCov::ResultMerger.resultset_path }

    let(:resultset_folder) { File.dirname(resultset_path) }

    let(:merged_result) do
      {
        "result1, result2" => {
          "coverage" => {
            source_fixture("sample.rb") => {
              lines: [1, 1, 2, 2, nil, nil, 2, 2, nil, nil]
            }
          }
        }
      }
    end

    let(:collated) do
      JSON.parse(File.read(resultset_path)).transform_values do |data|
        data["coverage"].values.first.transform_keys!(&:to_sym)
        data.reject { |k| k == "timestamp" }
      end
    end

    context "when no files to be merged" do
      it "shows an error message" do
        expect do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          SimpleCov.collate glob
        end.to raise_error("There are no reports to be merged")
      end
    end

    context "when files to be merged" do
      before do
        expect(SimpleCov).to receive(:run_exit_tasks!)
      end

      context "and a single report to be merged" do
        before do
          create_mergeable_report("result1", resultset1)
        end

        after do
          clear_mergeable_reports
        end

        it "creates a merged report identical to the original" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          SimpleCov.collate glob

          expected = {"result1" => {"coverage" => resultset1}}
          expect(collated).to eq(expected)
        end
      end

      context "and multiple reports to be merged" do
        before do
          create_mergeable_report("result1", resultset1)
          create_mergeable_report("result2", resultset2)
        end

        after do
          clear_mergeable_reports
        end

        it "creates a merged report" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          SimpleCov.collate glob

          expect(collated).to eq(merged_result)
        end
      end

      context "and multiple reports to be merged, one of them outdated" do
        before do
          create_mergeable_report("result1", resultset1)
          create_mergeable_report("result2", resultset2, outdated: true)
        end

        after do
          clear_mergeable_reports
        end

        it "ignores timeout by default creating a report with all values" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          SimpleCov.collate glob

          expect(collated).to eq(merged_result)
        end

        it "creates a merged report with only the results from the current resultset if ignore_timeout: false" do
          glob = Dir.glob("#{resultset_folder}/*.final", File::FNM_DOTMATCH)
          SimpleCov.collate glob, ignore_timeout: false

          expected = {"result1" => {"coverage" => resultset1}}
          expect(collated).to eq(expected)
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
        expected = {"result1, result2" => {"coverage" => {source_fixture("sample.rb") => {"lines" => [1, 1, 2, 2, nil, nil, 2, 2, nil, nil]}}}}
        expect(collated).to eq(expected)
      end
    end
  end

  # Normally wouldn't test private methods but just start has side effects that
  # cause errors so for time this is pragmatic (tm)
  describe ".start_coverage_measurement", if: SimpleCov.coverage_start_arguments_supported? do
    after :each do
      # SimpleCov is a Singleton/global object so once any test enables
      # any kind of coverage data it stays there.
      # Hence, we use clear_coverage_data to create a "clean slate" for these tests
      SimpleCov.clear_coverage_criteria
    end

    it "starts coverage in lines mode by default" do
      expect(Coverage).to receive(:start).with(lines: true)

      SimpleCov.send :start_coverage_measurement
    end

    it "starts coverage with lines and branches if branch coverage is activated" do
      expect(Coverage).to receive(:start).with(lines: true, branches: true)

      SimpleCov.enable_coverage :branch

      SimpleCov.send :start_coverage_measurement
    end

    it "starts coverage with lines and methods if method coverage is activated" do
      expect(Coverage).to receive(:start).with(lines: true, methods: true)

      SimpleCov.enable_coverage :method

      SimpleCov.send :start_coverage_measurement
    end
  end
end
