# frozen_string_literal: true

require "helper"
require "fileutils"

STUB_WORKING_DIRECTORY = "STUB_WORKING_DIRECTORY"

STUB_COMMAND_NAME = "STUB_COMMAND_NAME"

STUB_PROJECT_NAME = "STUB_PROJECT_NAME"

RSpec.describe SimpleCov::Formatter::JSONFormatter do
  subject(:formatter) { described_class.new(silent: true) }

  let(:fixed_time) { Time.new(2024, 1, 1, 0, 0, 0, "+00:00") }
  let(:result) do
    res = SimpleCov::Result.new({
                                  source_fixture("json/sample.rb") => {"lines" => [
                                    nil, 1, 1, 1, 1, nil, nil, 1, 1, nil, nil,
                                    1, 1, 0, nil, 1, nil, nil, nil, nil, 1, 0, nil, nil, nil
                                  ]}
                                })
    res.created_at = fixed_time
    res
  end

  # Prevent stale coverage.json from prior tests from triggering the
  # concurrent-overwrite warning.
  before do
    FileUtils.rm_f("tmp/coverage/coverage.json")
    SimpleCov.process_start_time = Time.now
  end

  # Outside SimpleCov.start, process_start_time is nil. Anchor it so the
  # concurrent-overwrite checks have a reference point.
  after { SimpleCov.process_start_time = nil }

  describe "with output_dir" do
    it "writes coverage.json into the explicit directory, not SimpleCov.coverage_path" do
      Dir.mktmpdir do |dir|
        described_class.new(silent: true, output_dir: dir).format(result)
        expect(File.exist?(File.join(dir, described_class::FILENAME))).to be true
        expect(File.exist?("tmp/coverage/coverage.json")).to be false
      end
    end

    it "names the explicit directory in the output message" do
      Dir.mktmpdir do |dir|
        out = capture_stderr { described_class.new(output_dir: dir).format(result) }
        expect(out).to include(File.join(dir, described_class::FILENAME))
      end
    end
  end

  describe "#output_message" do
    let(:loud_formatter) { described_class.new }

    it "prefixes the summary line with `JSON ` to distinguish it from the HTML formatter" do
      line_stat = SimpleCov::CoverageStatistics.new(covered: 10, missed: 0)
      result = instance_double(SimpleCov::Result,
                               command_name: "RSpec",
                               coverage_statistics: {line: line_stat})
      expect(loud_formatter.send(:output_message, result)).to start_with("JSON Coverage report generated")
    end

    it "floors the percent rather than rounding (so 22103/22104 doesn't print 100%)" do
      line_stat = SimpleCov::CoverageStatistics.new(covered: 22_103, missed: 1)
      result = instance_double(SimpleCov::Result,
                               command_name: "RSpec",
                               coverage_statistics: {line: line_stat})
      expect(loud_formatter.send(:output_message, result)).to include("(99.99%)")
    end

    context "when branch coverage is enabled" do
      let(:line_stat)   { SimpleCov::CoverageStatistics.new(covered: 10, missed: 0) }
      let(:branch_stat) { SimpleCov::CoverageStatistics.new(covered: 8,  missed: 2) }

      before { allow(SimpleCov).to receive(:branch_coverage?).and_return(true) }

      it "appends a Branch coverage line to the output_message" do
        result = instance_double(SimpleCov::Result,
                                 command_name: "RSpec", total_branches: 10,
                                 coverage_statistics: {line: line_stat, branch: branch_stat})
        expect(loud_formatter.send(:output_message, result)).to include("Branch coverage: 8 / 10 (80.00%)")
      end

      it "omits the Branch coverage line when total_branches is zero" do
        result = instance_double(SimpleCov::Result,
                                 command_name: "RSpec", total_branches: 0,
                                 coverage_statistics: {line: line_stat})
        expect(loud_formatter.send(:output_message, result)).not_to include("Branch coverage")
      end

      it "omits the Branch coverage line when total_branches is nil" do
        result = instance_double(SimpleCov::Result,
                                 command_name: "RSpec", total_branches: nil,
                                 coverage_statistics: {line: line_stat})
        expect(loud_formatter.send(:output_message, result)).not_to include("Branch coverage")
      end
    end

    context "when method coverage is enabled" do
      let(:line_stat)   { SimpleCov::CoverageStatistics.new(covered: 10, missed: 0) }
      let(:method_stat) { SimpleCov::CoverageStatistics.new(covered: 9,  missed: 1) }

      before { allow(SimpleCov).to receive(:method_coverage?).and_return(true) }

      it "appends a Method coverage line to the output_message" do
        result = instance_double(SimpleCov::Result,
                                 command_name: "RSpec", total_methods: 10,
                                 coverage_statistics: {line: line_stat, method: method_stat})
        expect(loud_formatter.send(:output_message, result)).to include("Method coverage: 9 / 10 (90.00%)")
      end

      it "omits the Method coverage line when total_methods is zero" do
        result = instance_double(SimpleCov::Result,
                                 command_name: "RSpec", total_methods: 0,
                                 coverage_statistics: {line: line_stat})
        expect(loud_formatter.send(:output_message, result)).not_to include("Method coverage")
      end

      it "omits the Method coverage line when total_methods is nil" do
        result = instance_double(SimpleCov::Result,
                                 command_name: "RSpec", total_methods: nil,
                                 coverage_statistics: {line: line_stat})
        expect(loud_formatter.send(:output_message, result)).not_to include("Method coverage")
      end
    end
  end

  describe "format" do
    context "with line coverage" do
      it "includes line coverage and covered_percent per file" do
        formatter.format(result)
        expect(json_output).to eq(json_result("sample"))
      end

      it "preserves raw percentage and strength precision" do
        unrounded_result = SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}})

        formatter.format(unrounded_result)

        expect(json_output.fetch("total").fetch("lines")).to include(
          "percent" => 66.66666666666667,
          "strength" => 0.6666666666666666
        )
        expect(json_output.fetch("coverage").fetch(project_fixture_filename("json/sample.rb"))).to include(
          "lines_covered_percent" => 66.66666666666667
        )
      end
    end

    context "with the source_in_json toggle" do
      let(:file_entry) { json_output.fetch("coverage").fetch(project_fixture_filename("json/sample.rb")) }

      it "includes the source array by default" do
        formatter.format(result)
        expect(file_entry).to have_key("source")
        expect(file_entry["source"]).to be_an(Array)
        expect(file_entry["source"]).not_to be_empty
      end

      it "omits the source array when SimpleCov.source_in_json is false" do
        allow(SimpleCov).to receive(:source_in_json).and_return(false)
        formatter.format(result)
        expect(file_entry).not_to have_key("source")
      end

      it "still includes line / branch / method sections when source is omitted" do
        allow(SimpleCov).to receive(:source_in_json).and_return(false)
        formatter.format(result)
        expect(file_entry).to include("lines", "covered_lines", "missed_lines", "total_lines", "lines_covered_percent")
      end
    end

    context "with branch coverage" do
      let(:original_lines) do
        [nil, 1, 1, 1, 1, nil, nil, 1, 1,
         nil, nil, 1, 1, 0, nil, 1, nil,
         nil, nil, nil, 1, 0, nil, nil, nil]
      end

      let(:original_branches) do
        {
          [:if, 0, 13, 4, 17, 7] => {
            [:then, 1, 14, 6, 14, 10] => 0,
            [:else, 2, 16, 6, 16, 10] => 1
          }
        }
      end

      let(:result) do
        res = SimpleCov::Result.new({
                                      source_fixture("json/sample.rb") => {
                                        "lines" => original_lines,
                                        "branches" => original_branches
                                      }
                                    })
        res.created_at = fixed_time
        res
      end

      before do
        enable_branch_coverage
      end

      it "includes branch data and branches_covered_percent per file" do
        formatter.format(result)
        expect(json_output).to eq(json_result("sample_with_branch"))
      end
    end

    context "with method coverage" do
      let(:original_lines) do
        [nil, 1, 1, 1, 1, nil, nil, 1, 1,
         nil, nil, 1, 1, 0, nil, 1, nil,
         nil, nil, nil, 1, 0, nil, nil, nil]
      end

      let(:original_methods) do
        {
          ["Foo", :initialize, 3, 2, 6, 5] => 1,
          ["Foo", :bar, 8, 2, 10, 5] => 1,
          ["Foo", :foo, 12, 2, 18, 5] => 1,
          ["Foo", :skipped, 21, 2, 23, 5] => 0
        }
      end

      let(:result) do
        res = SimpleCov::Result.new({
                                      source_fixture("json/sample.rb") => {
                                        "lines" => original_lines,
                                        "methods" => original_methods
                                      }
                                    })
        res.created_at = fixed_time
        res
      end

      before do
        enable_method_coverage
      end

      # total.methods.total is 3, not 4, because Foo#skipped is inside a simplecov:disable block
      it "includes methods array and methods_covered_percent per file" do
        formatter.format(result)
        expect(json_output).to eq(json_result("sample_with_method"))
      end
    end

    context "with minimum_coverage below threshold" do
      before do
        allow(SimpleCov).to receive(:minimum_coverage).and_return(line: 95)
      end

      it "reports the violation in errors" do
        formatter.format(result)
        errors = json_output.fetch("errors")
        expect(errors).to eq(
          "minimum_coverage" => {"lines" => {"expected" => 95, "actual" => 90.0}}
        )
      end
    end

    context "with minimum_coverage above threshold" do
      before do
        allow(SimpleCov).to receive(:minimum_coverage).and_return(line: 80)
      end

      it "returns empty errors" do
        formatter.format(result)
        expect(json_output.fetch("errors")).to eq({})
      end
    end

    context "with minimum_coverage keyed on :oneshot_line" do
      # `:oneshot_line` is a synonym for `:line` in stats — see #1170.
      before do
        allow(SimpleCov).to receive(:minimum_coverage).and_return(oneshot_line: 95)
      end

      it "reports the violation under :lines without raising" do
        formatter.format(result)
        errors = json_output.fetch("errors")
        expect(errors).to eq(
          "minimum_coverage" => {"lines" => {"expected" => 95, "actual" => 90.0}}
        )
      end
    end

    context "with minimum_coverage_by_file for lines" do
      before do
        allow(SimpleCov).to receive(:minimum_coverage_by_file).and_return(line: 95)
      end

      it "reports files below the threshold in errors" do
        formatter.format(result)
        errors = json_output.fetch("errors")
        expect(errors).to eq(
          "minimum_coverage_by_file" => {
            "lines" => {project_fixture_filename("json/sample.rb") => {"expected" => 95, "actual" => 90.0}}
          }
        )
      end
    end

    context "with minimum_coverage_by_file for branches" do
      let(:result) do
        SimpleCov::Result.new({
                                source_fixture("json/sample.rb") => {
                                  "lines" => [nil, 1, 1, 1, 1, nil, nil, 1, 1, nil, nil,
                                              1, 1, 0, nil, 1, nil, nil, nil, nil, 1, 0, nil, nil, nil],
                                  "branches" => {
                                    [:if, 0, 13, 4, 17, 7] => {
                                      [:then, 1, 14, 6, 14, 10] => 0,
                                      [:else, 2, 16, 6, 16, 10] => 1
                                    }
                                  }
                                }
                              })
      end

      before do
        enable_branch_coverage
        allow(SimpleCov).to receive(:minimum_coverage_by_file).and_return(branch: 75)
      end

      it "reports files below the threshold in errors" do
        formatter.format(result)
        errors = json_output.fetch("errors")
        expect(errors).to eq(
          "minimum_coverage_by_file" => {
            "branches" => {project_fixture_filename("json/sample.rb") => {"expected" => 75, "actual" => 50.0}}
          }
        )
      end
    end

    context "with minimum_coverage_by_file when all files pass" do
      before do
        allow(SimpleCov).to receive(:minimum_coverage_by_file).and_return(line: 80)
      end

      it "returns empty errors" do
        formatter.format(result)
        expect(json_output.fetch("errors")).to eq({})
      end
    end

    context "with a minimum_coverage_by_file per-path override" do
      before do
        allow(SimpleCov).to receive_messages(
          minimum_coverage_by_file: {},
          minimum_coverage_by_file_overrides: {project_fixture_filename("json/sample.rb") => {line: 100}}
        )
      end

      it "reports the file under its override threshold in errors" do
        formatter.format(result)
        errors = json_output.fetch("errors")
        expect(errors).to eq(
          "minimum_coverage_by_file" => {
            "lines" => {project_fixture_filename("json/sample.rb") => {"expected" => 100, "actual" => 90.0}}
          }
        )
      end
    end

    context "with minimum_coverage_by_group below threshold" do
      let(:sample_filename) { source_fixture("json/sample.rb") }
      let(:line_stats) { SimpleCov::CoverageStatistics.new(covered: 7, missed: 3) }

      let(:result) do
        res = SimpleCov::Result.new({
                                      sample_filename => {"lines" => [
                                        nil, 1, 1, 1, 1, nil, nil, 1, 1, nil, nil,
                                        1, 1, 0, nil, 1, nil, nil, nil, nil, 1, 0, nil, nil, nil
                                      ]}
                                    })

        mock_file_list = instance_double(SimpleCov::FileList,
                                         coverage_statistics: {line: line_stats},
                                         map: [sample_filename])
        allow(res).to receive_messages(groups: {"Models" => mock_file_list})
        res
      end

      before do
        allow(SimpleCov).to receive(:minimum_coverage_by_group).and_return("Models" => {line: 80})
      end

      it "reports the group violation in errors" do
        formatter.format(result)
        errors = json_output.fetch("errors")
        expect(errors).to eq(
          "minimum_coverage_by_group" => {
            "Models" => {"lines" => {"expected" => 80, "actual" => 70.0}}
          }
        )
      end
    end

    context "with maximum_coverage exceeded" do
      before do
        allow(SimpleCov).to receive(:maximum_coverage).and_return(line: 85)
      end

      it "reports the violation in errors" do
        formatter.format(result)
        errors = json_output.fetch("errors")
        expect(errors).to eq(
          "maximum_coverage" => {"lines" => {"expected" => 85, "actual" => 90.0}}
        )
      end
    end

    context "with maximum_coverage not exceeded" do
      before do
        allow(SimpleCov).to receive(:maximum_coverage).and_return(line: 95)
      end

      it "returns empty errors" do
        formatter.format(result)
        expect(json_output.fetch("errors")).to eq({})
      end
    end

    context "with maximum_coverage_drop exceeded" do
      before do
        allow(SimpleCov).to receive(:maximum_coverage_drop).and_return(line: 2)
        allow(SimpleCov::LastRun).to receive(:read).and_return({result: {line: 95.0}})
      end

      it "reports the drop in errors" do
        formatter.format(result)
        errors = json_output.fetch("errors")
        expect(errors).to eq(
          "maximum_coverage_drop" => {
            "lines" => {"maximum" => 2, "actual" => 5.0}
          }
        )
      end
    end

    context "with maximum_coverage_drop not exceeded" do
      before do
        allow(SimpleCov).to receive(:maximum_coverage_drop).and_return(line: 2)
        allow(SimpleCov::LastRun).to receive(:read).and_return({result: {line: 91.0}})
      end

      it "returns empty errors" do
        formatter.format(result)
        expect(json_output.fetch("errors")).to eq({})
      end
    end

    context "with maximum_coverage_drop and no last run" do
      before do
        allow(SimpleCov).to receive(:maximum_coverage_drop).and_return(line: 2)
        allow(SimpleCov::LastRun).to receive(:read).and_return(nil)
      end

      it "returns empty errors" do
        formatter.format(result)
        expect(json_output.fetch("errors")).to eq({})
      end
    end

    context "with groups" do
      let(:sample_filename) { source_fixture("json/sample.rb") }

      let(:line_stats) { SimpleCov::CoverageStatistics.new(covered: 8, missed: 2) }

      let(:result) do
        res = SimpleCov::Result.new({
                                      sample_filename => {"lines" => [
                                        nil, 1, 1, 1, 1, nil, nil, 1, 1, nil, nil,
                                        1, 1, 0, nil, 1, nil, nil, nil, nil, 1, 0, nil, nil, nil
                                      ]}
                                    })
        res.created_at = fixed_time

        # right now SimpleCov works mostly on global state, hence setting the groups that way
        # would be global state --> Mocking is better here. `map` ignores the block
        # and returns the stubbed value — so stub it to the project-relative path directly.
        mock_file_list = instance_double(SimpleCov::FileList,
                                         coverage_statistics: {line: line_stats},
                                         map: [project_fixture_filename("json/sample.rb")])
        allow(res).to receive_messages(
          groups: {"My Group" => mock_file_list}
        )
        res
      end

      it "displays groups correctly in the JSON" do
        formatter.format(result)
        expect(json_output).to eq(json_result("sample_groups"))
      end
    end

    context "when an existing coverage.json was written after this process started" do
      let(:coverage_path) { "tmp/coverage/coverage.json" }
      let(:future_timestamp) { (Time.now + 3600).iso8601 }

      before do
        FileUtils.mkdir_p("tmp/coverage")
        File.write(coverage_path, JSON.generate(meta: {timestamp: future_timestamp}))
      end

      it "warns that a concurrent process may have written it" do
        stderr = capture_stderr { formatter.format(result) }

        expect(stderr).to include("simplecov:")
        expect(stderr).to include(future_timestamp)
        expect(stderr).to include("concurrent test run")
      end

      it "still writes the new file" do
        capture_stderr { formatter.format(result) }

        expect(json_output.fetch("meta").fetch("timestamp")).to eq(fixed_time.iso8601(3))
      end
    end

    context "when an existing coverage.json predates this process" do
      before do
        FileUtils.mkdir_p("tmp/coverage")
        past_timestamp = (Time.now - 3600).iso8601
        File.write("tmp/coverage/coverage.json", JSON.generate(meta: {timestamp: past_timestamp}))
      end

      it "does not warn" do
        expect { formatter.format(result) }.not_to output.to_stderr
      end
    end

    context "when the existing coverage.json is malformed" do
      before do
        FileUtils.mkdir_p("tmp/coverage")
        File.write("tmp/coverage/coverage.json", "not-json")
      end

      it "does not warn or raise" do
        expect { formatter.format(result) }.not_to output.to_stderr
      end
    end

    context "with :line coverage disabled" do
      # Confirms the formatter doesn't emit `lines` / per-file
      # `lines_covered_percent` / `total_lines` keys when the line
      # criterion was switched off via `disable_coverage :line`.
      before do
        allow(SimpleCov).to receive(:coverage_criterion_enabled?).and_call_original
        allow(SimpleCov).to receive(:coverage_criterion_enabled?).with(:line).and_return(false)
        allow(SimpleCov).to receive(:coverage_criterion_enabled?).with(:oneshot_line).and_return(false)
        enable_branch_coverage
      end

      it "omits line keys from per-file output and totals" do
        result = SimpleCov::Result.new({
                                         source_fixture("json/sample.rb") => {
                                           "lines" => [nil, 1, 1, 0],
                                           "branches" => {[:if, 0, 1, 0, 4, 0] => {
                                             [:then, 1, 2, 2, 2, 6] => 1,
                                             [:else, 2, 3, 2, 3, 6] => 0
                                           }}
                                         }
                                       })
        result.created_at = fixed_time
        formatter.format(result)

        payload = json_output
        expect(payload["total"]).not_to include("lines")
        expect(payload["total"]).to include("branches")
        first_file_keys = payload["coverage"].values.first.keys
        expect(first_file_keys).not_to include("lines", "lines_covered_percent", "covered_lines", "total_lines")
      end
    end
  end

  def enable_branch_coverage
    allow(SimpleCov).to receive(:branch_coverage?).and_return(true)
  end

  def enable_method_coverage
    allow(SimpleCov).to receive(:method_coverage?).and_return(true)
  end

  def json_output
    JSON.parse(File.read("tmp/coverage/coverage.json"))
  end

  def json_result(filename)
    file = File.read(source_fixture("json/#{filename}.json"))
    file = replace_stubs(file)
    JSON.parse(file)
  end

  def project_fixture_filename(path)
    SimpleCov::SourceFile.new(source_fixture(path), []).project_filename
  end

  def replace_stubs(file)
    current_working_directory = File.expand_path("..", source_fixture_base_directory)
    file
      .gsub("/#{STUB_WORKING_DIRECTORY}/", "#{current_working_directory}/")
      .gsub("\"/#{STUB_WORKING_DIRECTORY}\"", "\"#{current_working_directory}\"")
      .gsub("\"#{STUB_COMMAND_NAME}\"", "\"#{SimpleCov.command_name}\"")
      .gsub("\"#{STUB_PROJECT_NAME}\"", "\"#{SimpleCov.project_name}\"")
  end
end
