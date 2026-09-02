# frozen_string_literal: true

require "helper"
require "json"
require "json_schemer"

describe "coverage.json schema" do
  let(:schema_doc) { JSON.parse(File.read(schema_path)) }
  let(:alias_doc) { JSON.parse(File.read(alias_path)) }
  let(:schemer) { JSONSchemer.schema(schema_doc) }

  def schema_path = File.expand_path("../../schemas/coverage-v1.3.schema.json", __dir__)

  def alias_path = File.expand_path("../../schemas/coverage.schema.json", __dir__)

  def validate_against_schema(document)
    schemer.validate(document).map { |e| "#{e["data_pointer"]}: #{e["error"]}" }
  end

  def expect_schema_valid(document)
    errors = validate_against_schema(document)
    expect(errors).to be_empty, "schema validation failed:\n  #{errors.join("\n  ")}"
  end

  def project_fixture_filename(path)
    SimpleCov::SourceFile.new(source_fixture(path), []).project_filename
  end

  it "is itself a valid JSON Schema (2020-12)" do
    expect(JSONSchemer.draft202012.validate(schema_doc).to_a).to be_empty
  end

  it "declares 2020-12 as its meta-schema" do
    expect(schema_doc.fetch("$schema")).to eq("https://json-schema.org/draft/2020-12/schema")
  end

  it "ships an unversioned alias that mirrors the latest versioned canonical" do
    alias_metadata_keys = %w[$id title description]
    expect(alias_doc.except(*alias_metadata_keys)).to eq(schema_doc.except(*alias_metadata_keys))
  end

  it "pins the versioned canonical's $id to a versioned URL" do
    expect(schema_doc.fetch("$id")).to match(%r{/schemas/coverage-v\d+\.\d+\.schema\.json\z})
  end

  it "rejects a document claiming a foreign schema_version" do
    document = JSON.parse(File.read(source_fixture("json/sample.json")))
    document["meta"]["schema_version"] = "0.0"
    errors = validate_against_schema(document)
    expect(errors).not_to be_empty
  end

  context "with shipped fixtures" do
    %w[sample sample_with_branch sample_with_method sample_groups].each do |basename|
      it "validates #{basename}.json" do
        expect_schema_valid(JSON.parse(File.read(source_fixture("json/#{basename}.json"))))
      end
    end
  end

  context "with fresh JSONFormatter output" do
    let(:formatter) { SimpleCov::Formatter::JSONFormatter.new(silent: true) }

    before do
      FileUtils.rm_f(File.join(SimpleCov.coverage_path, "coverage.json"))
      SimpleCov.process_start_time = Time.now
    end

    after { SimpleCov.process_start_time = nil }

    def emit(result)
      result.created_at = Time.new(2024, 1, 1, 0, 0, 0, "+00:00")
      formatter.format(result)
      JSON.parse(File.read(File.join(SimpleCov.coverage_path, "coverage.json")))
    end

    def simple_result
      SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}})
    end

    def branch_result
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

    def method_result
      SimpleCov::Result.new({
        source_fixture("json/sample.rb") => {
          "lines" => [nil, 1, 1, 1, 1, nil, nil, 1, 1, nil, nil,
            1, 1, 0, nil, 1, nil, nil, nil, nil, 1, 0, nil, nil, nil],
          "methods" => {
            ["Foo", :initialize, 3, 2, 6, 5] => 1,
            ["Foo", :bar, 8, 2, 10, 5] => 1,
            ["Foo", :foo, 12, 2, 18, 5] => 1
          }
        }
      })
    end

    def line_disabled_result
      SimpleCov::Result.new({
        source_fixture("json/sample.rb") => {
          "lines" => [nil, 1, 1, 0],
          "branches" => {[:if, 0, 1, 0, 4, 0] => {
            [:then, 1, 2, 2, 2, 6] => 1,
            [:else, 2, 3, 2, 3, 6] => 0
          }}
        }
      })
    end

    it "validates a minimal line-coverage result" do
      result = SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, nil]}})

      expect_schema_valid(emit(result))
    end

    context "without SimpleCov.source_in_json" do
      let(:document) { emit(SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, nil]}})) }

      before { allow(SimpleCov).to receive(:source_in_json).and_return(false) }

      it "emits no per-file source array" do
        expect(document.fetch("coverage").values.first).not_to have_key("source")
      end

      it "validates" do
        expect_schema_valid(document)
      end
    end

    it "validates a result with branch coverage enabled" do
      allow(SimpleCov).to receive(:branch_coverage?).and_return(true)

      expect_schema_valid(emit(branch_result))
    end

    it "validates a result with method coverage enabled" do
      allow(SimpleCov).to receive(:method_coverage?).and_return(true)

      expect_schema_valid(emit(method_result))
    end

    context "when line coverage is disabled" do
      let(:document) { emit(line_disabled_result) }

      before { allow(SimpleCov).to receive_messages(line_coverage?: false, branch_coverage?: true) }

      it "records the disabled criterion in meta" do
        expect(document.fetch("meta").fetch("line_coverage")).to be(false)
      end

      it "omits lines from the totals" do
        expect(document.fetch("total")).not_to have_key("lines")
      end

      it "omits lines from every file" do
        expect(document.fetch("coverage").values.first).not_to have_key("lines")
      end

      it "validates" do
        expect_schema_valid(document)
      end
    end

    context "with a context map" do
      let(:document) do
        emit(SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}}, contexts: context_map))
      end

      def context_map
        map = SimpleCov::ContextMap.new
        map.record("spec/sample_spec.rb:4", source_fixture("json/sample.rb") => 0b101)
        map.record("spec/quiet_spec.rb:9", {})
        map
      end

      it "lists every context at document level" do
        expect(document.fetch("contexts")).to eq(["spec/sample_spec.rb:4", "spec/quiet_spec.rb:9"])
      end

      it "carries the bitmap table at file level" do
        expect(document.fetch("coverage").values.first.fetch("contexts")).to eq("0" => "5")
      end

      it "validates" do
        expect_schema_valid(document)
      end
    end

    context "with a context map that touched only one of two files" do
      let(:document) { emit(partly_touched_result) }

      def partly_touched_result
        map = SimpleCov::ContextMap.new
        map.record("spec/sample_spec.rb:4", source_fixture("sample.rb") => 0b1)
        SimpleCov::Result.new(
          {
            source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]},
            source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}
          },
          contexts: map
        )
      end

      it "omits the untouched file's empty bitmap table" do
        untouched = document.fetch("coverage").fetch(project_fixture_filename("json/sample.rb"))

        expect(untouched).not_to have_key("contexts")
      end

      it "validates" do
        expect_schema_valid(document)
      end
    end

    context "with an empty context map" do
      let(:document) do
        emit(SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}},
          contexts: SimpleCov::ContextMap.new))
      end

      it "keeps an empty context list" do
        expect(document.fetch("contexts")).to eq([])
      end

      it "validates" do
        expect_schema_valid(document)
      end
    end

    context "without a context map" do
      let(:document) { emit(SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, nil]}})) }

      it "omits the document-level contexts key" do
        expect(document).not_to have_key("contexts")
      end

      it "omits every file-level contexts key" do
        expect(document.fetch("coverage").values.first).not_to have_key("contexts")
      end

      it "validates" do
        expect_schema_valid(document)
      end
    end

    context "without a recorded past" do
      before { allow(SimpleCov::History).to receive(:read).and_return([]) }

      it "omits the history section" do
        expect(emit(simple_result)).not_to have_key("history")
      end
    end

    context "with a run history" do
      let(:document) { emit(simple_result) }

      before do
        allow(SimpleCov::History).to receive_messages(
          read: [{"created_at" => "2026-08-24T12:00:00Z", "branch" => "main", "commit" => "abc",
                  "totals" => {"line" => 90.0}, "groups" => {}, "files" => {"lib/a.rb" => {"line" => 90.0}}}],
          git_info: [nil, nil]
        )
      end

      it "appends this run to the recorded past" do
        expect(document.fetch("history").length).to eq(2)
      end

      it "records this run's totals" do
        expect(document.fetch("history").last.fetch("totals")).to eq("line" => 66.66)
      end

      it "validates" do
        expect_schema_valid(document)
      end
    end

    context "without a production store configured" do
      it "omits the production section" do
        expect(emit(simple_result)).not_to have_key("production")
      end
    end

    context "with production coverage" do
      let(:document) { emit(simple_result) }

      before do
        allow(SimpleCov::Formatter::JSONFormatter::ProductionSectionFormatter).to receive(:call).and_return(
          started_at: "2026-08-01T05:00:00Z", updated_at: "2026-08-25T11:00:00Z",
          files: {"lib/a.rb" => {lines: [1, 3], last_seen: "2026-08-25T10:00:00Z"},
                  "lib/b.rb" => {lines: [2]}}
        )
      end

      it "lists every file the store carries" do
        expect(document.fetch("production").fetch("files").keys).to eq(["lib/a.rb", "lib/b.rb"])
      end

      it "validates" do
        expect_schema_valid(document)
      end
    end

    context "with errors populated" do
      let(:result) do
        SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}})
      end

      def stub_baseline(floor)
        baseline = SimpleCov::Baseline.new(project_fixture_filename("json/sample.rb") => {line: floor})
        allow(SimpleCov).to receive(:baseline).and_return(baseline)
      end

      def baseline_violation(document)
        document.dig("errors", "baseline", project_fixture_filename("json/sample.rb"), "lines")
      end

      def stub_group_minimum
        line_stats = SimpleCov::CoverageStatistics.new(covered: 7, missed: 3)
        mock_file_list = instance_double(SimpleCov::FileList,
          coverage_statistics: {line: line_stats},
          map: [source_fixture("json/sample.rb")])
        allow(result).to receive(:groups).and_return("Models" => mock_file_list)
        allow(SimpleCov).to receive(:minimum_coverage_by_group).and_return("Models" => {line: 80})
      end

      it "validates a minimum_coverage violation" do
        allow(SimpleCov).to receive(:minimum_coverage).and_return(line: 95)
        document = emit(result)

        expect(document.dig("errors", "minimum_coverage")).not_to be_nil
        expect_schema_valid(document)
      end

      it "validates a minimum_coverage_by_file violation" do
        allow(SimpleCov).to receive(:minimum_coverage_by_file).and_return(line: 95)
        document = emit(result)

        expect(document.dig("errors", "minimum_coverage_by_file")).not_to be_nil
        expect_schema_valid(document)
      end

      it "validates a minimum_coverage_by_group violation" do
        stub_group_minimum
        document = emit(result)

        expect(document.dig("errors", "minimum_coverage_by_group")).not_to be_nil
        expect_schema_valid(document)
      end

      it "validates a baseline violation" do
        stub_baseline(SimpleCov::Baseline::Floor.new(percent: 90.0, missed: 0))
        document = emit(result)

        expect(baseline_violation(document)).to include("expected" => 90.0, "actual_missed" => 1, "allowed_missed" => 0)
        expect_schema_valid(document)
      end

      it "validates a percent-only baseline violation, which omits allowed_missed" do
        stub_baseline(SimpleCov::Baseline::Floor.new(percent: 90.0, missed: nil))
        document = emit(result)

        expect(baseline_violation(document)).not_to have_key("allowed_missed")
        expect_schema_valid(document)
      end

      it "validates a maximum_coverage violation" do
        allow(SimpleCov).to receive(:maximum_coverage).and_return(line: 50)
        document = emit(result)

        expect(document.dig("errors", "maximum_coverage")).not_to be_nil
        expect_schema_valid(document)
      end

      it "validates a maximum_coverage_drop violation" do
        allow(SimpleCov).to receive(:maximum_coverage_drop).and_return(line: 2)
        allow(SimpleCov::LastRun).to receive(:read).and_return({result: {line: 95.0}})
        document = emit(result)

        expect(document.dig("errors", "maximum_coverage_drop")).not_to be_nil
        expect_schema_valid(document)
      end

      it "validates a maximum_missed violation" do
        allow(SimpleCov).to receive(:maximum_missed).and_return(line: 0)
        document = emit(result)

        expect(document.dig("errors", "maximum_missed", "lines")).to eq("maximum" => 0, "actual" => 1)
        expect_schema_valid(document)
      end

      it "validates a maximum_missed_per_file violation" do
        allow(SimpleCov).to receive(:maximum_missed_per_file).and_return(line: 0)
        document = emit(result)
        violation = document.dig("errors", "maximum_missed_per_file", project_fixture_filename("json/sample.rb"))

        expect(violation).to eq("lines" => {"maximum" => 0, "actual" => 1})
        expect_schema_valid(document)
      end
    end
  end
end
