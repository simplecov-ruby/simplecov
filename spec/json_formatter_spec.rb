# frozen_string_literal: true

require "helper"
require "fileutils"

describe SimpleCov::Formatter::JSONFormatter do
  subject { described_class.new(silent: true) }

  let(:fixed_time) { Time.new(2024, 1, 1, 0, 0, 0, "+00:00") }

  # Prevent stale coverage.json from prior tests from triggering the
  # concurrent-overwrite warning.
  before { FileUtils.rm_f("tmp/coverage/coverage.json") }

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

  describe "format" do
    context "with line coverage" do
      it "includes line coverage and covered_percent per file" do
        subject.format(result)
        expect(json_output).to eq(json_result("sample"))
      end

      it "preserves raw percentage and strength precision" do
        unrounded_result = SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}})

        subject.format(unrounded_result)

        expect(json_output.fetch("total").fetch("lines")).to include(
          "percent" => 66.66666666666667,
          "strength" => 0.6666666666666666
        )
        expect(json_output.fetch("coverage").fetch(project_fixture_filename("json/sample.rb"))).to include(
          "lines_covered_percent" => 66.66666666666667
        )
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
        subject.format(result)
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

      # total.methods.total is 3, not 4, because Foo#skipped is inside a :nocov: block
      it "includes methods array and methods_covered_percent per file" do
        subject.format(result)
        expect(json_output).to eq(json_result("sample_with_method"))
      end
    end

    context "with minimum_coverage below threshold" do
      before do
        allow(SimpleCov).to receive(:minimum_coverage).and_return(line: 95)
      end

      it "reports the violation in errors" do
        subject.format(result)
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
        subject.format(result)
        expect(json_output.fetch("errors")).to eq({})
      end
    end

    context "with minimum_coverage_by_file for lines" do
      before do
        allow(SimpleCov).to receive(:minimum_coverage_by_file).and_return(line: 95)
      end

      it "reports files below the threshold in errors" do
        subject.format(result)
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
        subject.format(result)
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
        subject.format(result)
        expect(json_output.fetch("errors")).to eq({})
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

        mock_file_list = double("File List",
                                coverage_statistics: {line: line_stats},
                                map: [sample_filename])
        allow(res).to receive_messages(groups: {"Models" => mock_file_list})
        res
      end

      before do
        allow(SimpleCov).to receive(:minimum_coverage_by_group).and_return("Models" => {line: 80})
      end

      it "reports the group violation in errors" do
        subject.format(result)
        errors = json_output.fetch("errors")
        expect(errors).to eq(
          "minimum_coverage_by_group" => {
            "Models" => {"lines" => {"expected" => 80, "actual" => 70.0}}
          }
        )
      end
    end

    context "with maximum_coverage_drop exceeded" do
      before do
        allow(SimpleCov).to receive(:maximum_coverage_drop).and_return(line: 2)
        allow(SimpleCov::LastRun).to receive(:read).and_return({result: {line: 95.0}})
      end

      it "reports the drop in errors" do
        subject.format(result)
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
        subject.format(result)
        expect(json_output.fetch("errors")).to eq({})
      end
    end

    context "with maximum_coverage_drop and no last run" do
      before do
        allow(SimpleCov).to receive(:maximum_coverage_drop).and_return(line: 2)
        allow(SimpleCov::LastRun).to receive(:read).and_return(nil)
      end

      it "returns empty errors" do
        subject.format(result)
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
        mock_file_list = double("File List",
                                coverage_statistics: {line: line_stats},
                                map: [project_fixture_filename("json/sample.rb")])
        allow(res).to receive_messages(
          groups: {"My Group" => mock_file_list}
        )
        res
      end

      it "displays groups correctly in the JSON" do
        subject.format(result)
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
        stderr = capture_stderr { subject.format(result) }

        expect(stderr).to include("simplecov:")
        expect(stderr).to include(future_timestamp)
        expect(stderr).to include("concurrent test run")
      end

      it "still writes the new file" do
        capture_stderr { subject.format(result) }

        expect(json_output.fetch("meta").fetch("timestamp")).to eq(fixed_time.iso8601)
      end
    end

    context "when an existing coverage.json predates this process" do
      before do
        FileUtils.mkdir_p("tmp/coverage")
        past_timestamp = (Time.now - 3600).iso8601
        File.write("tmp/coverage/coverage.json", JSON.generate(meta: {timestamp: past_timestamp}))
      end

      it "does not warn" do
        stderr = capture_stderr { subject.format(result) }

        expect(stderr).to be_empty
      end
    end

    context "when the existing coverage.json is malformed" do
      before do
        FileUtils.mkdir_p("tmp/coverage")
        File.write("tmp/coverage/coverage.json", "not-json")
      end

      it "does not warn or raise" do
        stderr = capture_stderr { subject.format(result) }

        expect(stderr).to be_empty
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
    source_fixture(path).delete_prefix(SimpleCov.root)
  end

  STUB_WORKING_DIRECTORY = "STUB_WORKING_DIRECTORY"
  STUB_COMMAND_NAME = "STUB_COMMAND_NAME"
  STUB_PROJECT_NAME = "STUB_PROJECT_NAME"

  def replace_stubs(file)
    current_working_directory = File.expand_path("..", File.dirname(__FILE__))
    file
      .gsub("/#{STUB_WORKING_DIRECTORY}/", "#{current_working_directory}/")
      .gsub("\"/#{STUB_WORKING_DIRECTORY}\"", "\"#{current_working_directory}\"")
      .gsub("\"#{STUB_COMMAND_NAME}\"", "\"#{SimpleCov.command_name}\"")
      .gsub("\"#{STUB_PROJECT_NAME}\"", "\"#{SimpleCov.project_name}\"")
  end
end
