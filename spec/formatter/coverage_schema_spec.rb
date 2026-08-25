# frozen_string_literal: true

require "helper"
require "json"
require "json_schemer"

# Validates that every shape JSONFormatter is expected to emit conforms to
# the contract in schemas/coverage-v1.0.schema.json. The schema is
# published as the public contract for coverage.json consumers, this
# spec catches drift between code and schema at test time so neither
# can rot independently.
describe "coverage.json schema" do # rubocop:disable RSpec/DescribeClass
  let(:schema_path) { File.expand_path("../../schemas/coverage-v1.2.schema.json", __dir__) }
  let(:alias_path)  { File.expand_path("../../schemas/coverage.schema.json", __dir__) }
  let(:schema_doc)  { JSON.parse(File.read(schema_path)) }
  let(:alias_doc)   { JSON.parse(File.read(alias_path)) }
  let(:schemer)     { JSONSchemer.schema(schema_doc) }

  def validate_against_schema(document)
    schemer.validate(document).map { |e| "#{e['data_pointer']}: #{e['error']}" }
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

  # The unversioned alias is a convenience pointer to the latest version.
  # Allow only the metadata triple to diverge (title, description, $id)
  # so the canonical and alias can't drift in shape unnoticed.
  it "ships an unversioned alias that mirrors the latest versioned canonical" do
    alias_metadata_keys = %w[$id title description]
    expect(alias_doc.except(*alias_metadata_keys)).to eq(schema_doc.except(*alias_metadata_keys))
  end

  it "pins the versioned canonical's $id to a versioned URL" do
    expect(schema_doc.fetch("$id")).to match(%r{/schemas/coverage-v\d+\.\d+\.schema\.json\z})
  end

  # Guards against drift: a document claiming a foreign schema_version
  # must not quietly validate against whatever the current contract is.
  # "0.0" is used because the schema started at 1.0 and only bumps
  # upward — a pre-1.0 version string will never match any future
  # `const`, so this test stays valid across version bumps.
  it "rejects a document claiming a foreign schema_version" do
    document = JSON.parse(File.read(source_fixture("json/sample.json")))
    document["meta"]["schema_version"] = "0.0"
    errors = validate_against_schema(document)
    expect(errors).not_to be_empty
  end

  context "with shipped fixtures" do
    %w[sample sample_with_branch sample_with_method sample_groups].each do |basename|
      it "validates #{basename}.json" do
        document = JSON.parse(File.read(source_fixture("json/#{basename}.json")))
        errors = validate_against_schema(document)
        expect(errors).to be_empty, "schema validation failed:\n  #{errors.join("\n  ")}"
      end
    end
  end

  context "with fresh JSONFormatter output" do
    let(:fixed_time) { Time.new(2024, 1, 1, 0, 0, 0, "+00:00") }
    let(:formatter)  { SimpleCov::Formatter::JSONFormatter.new(silent: true) }

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

    it "validates a minimal line-coverage result" do
      result = SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, nil]}})
      errors = validate_against_schema(emit(result))
      expect(errors).to be_empty, errors.join("\n")
    end

    it "validates a result emitted with SimpleCov.source_in_json off (no per-file `source` array)" do
      allow(SimpleCov).to receive(:source_in_json).and_return(false)
      result = SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, nil]}})
      document = emit(result)
      # Sanity: the `source` field really is omitted, not just empty.
      expect(document.fetch("coverage").values.first).not_to have_key("source")
      errors = validate_against_schema(document)
      expect(errors).to be_empty, errors.join("\n")
    end

    it "validates a result with branch coverage enabled" do
      allow(SimpleCov).to receive(:branch_coverage?).and_return(true)
      result = SimpleCov::Result.new({
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
      errors = validate_against_schema(emit(result))
      expect(errors).to be_empty, errors.join("\n")
    end

    # `disable_coverage :line` is a real configuration. The formatter
    # then drops all line keys from `total`, per-file payloads, and
    # group totals. Guard against the schema drifting back into
    # requiring those keys.
    it "validates a result emitted with line coverage disabled" do
      allow(SimpleCov).to receive_messages(line_coverage?: false, branch_coverage?: true)
      result = SimpleCov::Result.new({
                                       source_fixture("json/sample.rb") => {
                                         "lines" => [nil, 1, 1, 0],
                                         "branches" => {[:if, 0, 1, 0, 4, 0] => {
                                           [:then, 1, 2, 2, 2, 6] => 1,
                                           [:else, 2, 3, 2, 3, 6] => 0
                                         }}
                                       }
                                     })
      document = emit(result)
      expect(document.fetch("meta").fetch("line_coverage")).to be(false)
      expect(document.fetch("total")).not_to have_key("lines")
      expect(document.fetch("coverage").values.first).not_to have_key("lines")
      errors = validate_against_schema(document)
      expect(errors).to be_empty, errors.join("\n")
    end

    it "validates a result carrying a context map, at document and file level" do
      map = SimpleCov::ContextMap.new
      map.record("spec/sample_spec.rb:4", source_fixture("json/sample.rb") => 0b101)
      map.record("spec/quiet_spec.rb:9", {})
      result = SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}}, contexts: map)

      document = emit(result)

      expect(document.fetch("contexts")).to eq(["spec/sample_spec.rb:4", "spec/quiet_spec.rb:9"])
      expect(document.fetch("coverage").values.first.fetch("contexts")).to eq("0" => "5")
      errors = validate_against_schema(document)
      expect(errors).to be_empty, errors.join("\n")
    end

    # An empty map still signals "contexts were recorded" (the run tracked
    # and nothing ran), while an untouched file simply has no bitmaps to
    # carry.
    it "keeps an empty context list but omits a file's empty bitmap table" do
      map = SimpleCov::ContextMap.new
      map.record("spec/sample_spec.rb:4", source_fixture("sample.rb") => 0b1)
      result = SimpleCov::Result.new(
        {
          source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]},
          source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}
        },
        contexts: map
      )

      document = emit(result)

      untouched = document.fetch("coverage").fetch(project_fixture_filename("json/sample.rb"))
      expect(untouched).not_to have_key("contexts")
      errors = validate_against_schema(document)
      expect(errors).to be_empty, errors.join("\n")

      empty = emit(SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}},
                                         contexts: SimpleCov::ContextMap.new))
      expect(empty.fetch("contexts")).to eq([])
      expect(validate_against_schema(empty)).to be_empty
    end

    it "omits the contexts keys entirely for a result that carries no map" do
      result = SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, nil]}})

      document = emit(result)

      expect(document).not_to have_key("contexts")
      expect(document.fetch("coverage").values.first).not_to have_key("contexts")
      expect(validate_against_schema(document)).to be_empty
    end

    it "validates a result with method coverage enabled" do
      allow(SimpleCov).to receive(:method_coverage?).and_return(true)
      result = SimpleCov::Result.new({
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
      errors = validate_against_schema(emit(result))
      expect(errors).to be_empty, errors.join("\n")
    end

    # The `errors` object is part of the public contract too; validate each
    # violation shape end-to-end so the schema can't drift away from what
    # the formatter actually emits when thresholds trip.
    context "with errors populated" do
      let(:result) do
        SimpleCov::Result.new({source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}})
      end

      it "validates a minimum_coverage violation" do
        allow(SimpleCov).to receive(:minimum_coverage).and_return(line: 95)
        document = emit(result)
        expect(document.dig("errors", "minimum_coverage")).not_to be_nil
        errors = validate_against_schema(document)
        expect(errors).to be_empty, errors.join("\n")
      end

      it "validates a minimum_coverage_by_file violation" do
        allow(SimpleCov).to receive(:minimum_coverage_by_file).and_return(line: 95)
        document = emit(result)
        expect(document.dig("errors", "minimum_coverage_by_file")).not_to be_nil
        errors = validate_against_schema(document)
        expect(errors).to be_empty, errors.join("\n")
      end

      it "validates a minimum_coverage_by_group violation" do
        line_stats = SimpleCov::CoverageStatistics.new(covered: 7, missed: 3)
        mock_file_list = instance_double(SimpleCov::FileList,
                                         coverage_statistics: {line: line_stats},
                                         map: [source_fixture("json/sample.rb")])
        allow(result).to receive(:groups).and_return("Models" => mock_file_list)
        allow(SimpleCov).to receive(:minimum_coverage_by_group).and_return("Models" => {line: 80})

        document = emit(result)
        expect(document.dig("errors", "minimum_coverage_by_group")).not_to be_nil
        errors = validate_against_schema(document)
        expect(errors).to be_empty, errors.join("\n")
      end

      it "validates a baseline violation" do
        stub_baseline(SimpleCov::Baseline::Floor.new(percent: 90.0, missed: 0))

        document = emit(result)
        violation = document.dig("errors", "baseline", project_fixture_filename("json/sample.rb"), "lines")
        expect(violation).to include("expected" => 90.0, "actual_missed" => 1, "allowed_missed" => 0)
        errors = validate_against_schema(document)
        expect(errors).to be_empty, errors.join("\n")
      end

      it "validates a percent-only baseline violation, which omits allowed_missed" do
        stub_baseline(SimpleCov::Baseline::Floor.new(percent: 90.0, missed: nil))

        document = emit(result)
        violation = document.dig("errors", "baseline", project_fixture_filename("json/sample.rb"), "lines")
        expect(violation).not_to have_key("allowed_missed")
        errors = validate_against_schema(document)
        expect(errors).to be_empty, errors.join("\n")
      end

      def stub_baseline(floor)
        baseline = SimpleCov::Baseline.new(project_fixture_filename("json/sample.rb") => {line: floor})
        allow(SimpleCov).to receive(:baseline).and_return(baseline)
      end

      it "validates a maximum_coverage violation" do
        allow(SimpleCov).to receive(:maximum_coverage).and_return(line: 50)
        document = emit(result)
        expect(document.dig("errors", "maximum_coverage")).not_to be_nil
        errors = validate_against_schema(document)
        expect(errors).to be_empty, errors.join("\n")
      end

      it "validates a maximum_coverage_drop violation" do
        allow(SimpleCov).to receive(:maximum_coverage_drop).and_return(line: 2)
        allow(SimpleCov::LastRun).to receive(:read).and_return({result: {line: 95.0}})
        document = emit(result)
        expect(document.dig("errors", "maximum_coverage_drop")).not_to be_nil
        errors = validate_against_schema(document)
        expect(errors).to be_empty, errors.join("\n")
      end
    end
  end
end
