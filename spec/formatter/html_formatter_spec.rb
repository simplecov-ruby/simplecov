# frozen_string_literal: true

require "helper"
require "fileutils"
require "json"
require "support/coverage_fixtures"

describe SimpleCov::Formatter::HTMLFormatter do
  subject(:formatter) { described_class.new(silent: true) }

  let(:loud_formatter) { described_class.new(silent: false) }
  let(:coverage_dir)   { SimpleCov.coverage_dir }
  let(:fixtures_path)  { File.join(source_fixture_base_directory, "fixtures") }

  before do
    FileUtils.rm_rf(coverage_dir)
    FileUtils.mkdir_p(coverage_dir)
  end

  def fixture_path(name)
    File.join(fixtures_path, name)
  end

  def make_result(coverage = {"sample.rb" => CoverageFixtures::SAMPLE_RB})
    SimpleCov::Result.new(coverage.transform_keys { |name| fixture_path(name) })
  end

  def coverage_data(dir = coverage_dir)
    content = File.read(File.join(dir, "coverage_data.js"))
    json_str = content.sub("window.SIMPLECOV_DATA = ", "").chomp(";\n")
    JSON.parse(json_str)
  end

  describe "DATA_FILENAME" do
    it "is the conventional coverage_data.js" do
      expect(described_class::DATA_FILENAME).to eq "coverage_data.js"
    end
  end

  describe "#initialize" do
    it "defaults silent to false" do
      expect(described_class.new.instance_variable_get(:@silent)).to be_falsey
    end

    it "honours an explicit silent: true" do
      expect(described_class.new(silent: true).instance_variable_get(:@silent)).to be true
    end
  end

  describe "#format" do
    before { formatter.format(make_result) }

    it "writes coverage_data.js into the coverage dir" do
      expect(File).to exist(File.join(coverage_dir, "coverage_data.js"))
    end

    it "writes coverage_data.js as a `window.SIMPLECOV_DATA = ...;` assignment" do
      content = File.read(File.join(coverage_dir, "coverage_data.js"))

      expect(content).to start_with("window.SIMPLECOV_DATA = ")
      expect(content).to end_with(";\n")
    end

    it "embeds parseable JSON in coverage_data.js" do
      data = coverage_data

      expect(data).to be_a(Hash)
      expect(data).to include("meta", "coverage", "total")
    end

    it "copies the static index.html alongside the data file" do
      expect(File).to exist(File.join(coverage_dir, "index.html"))
    end

    it "copies the static application.js" do
      expect(File).to exist(File.join(coverage_dir, "application.js"))
    end

    it "copies the static application.css" do
      expect(File).to exist(File.join(coverage_dir, "application.css"))
    end

    it "copies all three favicon variants" do
      %w[favicon_green.png favicon_red.png favicon_yellow.png].each do |name|
        expect(File).to exist(File.join(coverage_dir, name))
      end
    end

    it "also writes coverage.json next to the HTML report" do
      expect(File).to exist(File.join(coverage_dir, "coverage.json"))
    end

    it "embeds the source code of each file in the coverage payload" do
      file_data = coverage_data["coverage"].values.first

      expect(file_data).to include("source")
      expect(file_data["source"]).to be_a(Array)
      expect(file_data["source"]).not_to be_empty
    end

    it "embeds the metadata section in the coverage payload" do
      meta = coverage_data["meta"]

      expect(meta).to include("simplecov_version", "command_name", "project_name", "timestamp", "root")
      expect(meta["branch_coverage"]).to be(true).or be(false)
      expect(meta["method_coverage"]).to be(true).or be(false)
    end
  end

  describe "#format output behaviour" do
    it "prints a `Coverage report generated` line when not silent" do
      expect { loud_formatter.format(make_result) }.to output(/Coverage report generated/).to_stdout
    end

    it "prints the LOC stats when not silent" do
      expect { loud_formatter.format(make_result) }.to output(%r{\d+ / \d+ LOC}).to_stdout
    end

    it "stays quiet when silent: true" do
      expect { formatter.format(make_result) }.not_to output.to_stdout
    end
  end

  describe "#format_from_json" do
    let(:standalone_dir) { File.join(coverage_dir, "standalone") }

    before do
      formatter.format(make_result)
      described_class.new.format_from_json(File.join(coverage_dir, "coverage.json"), standalone_dir)
    end

    it "writes the data file and copies the static assets into the target dir" do
      %w[coverage_data.js index.html application.js].each do |name|
        expect(File).to exist(File.join(standalone_dir, name))
      end
    end

    it "produces a coverage_data.js with the same shape as the in-process format run" do
      data = coverage_data(standalone_dir)

      expect(data).to include("meta", "coverage")
    end
  end

  describe "integration with the full ALL_FIXTURES set" do
    let!(:original_criteria) { SimpleCov.coverage_criteria.dup }
    let!(:original_filters)  { SimpleCov.filters.dup }

    let(:full_coverage) { CoverageFixtures::ALL_FIXTURES }

    before do
      SimpleCov.enable_coverage(:branch)
      SimpleCov.filters.clear
      formatter.format(make_result(full_coverage))
    end

    after do
      SimpleCov.clear_coverage_criteria
      original_criteria.each { |criterion| SimpleCov.enable_coverage(criterion) }
      SimpleCov.filters.replace(original_filters)
    end

    it "computes the expected total line-coverage percentage" do
      expect(coverage_data["total"]["lines"]["percent"]).to be_within(0.01).of(74.12)
    end

    it "reports the expected per-file line coverages" do
      pcts = coverage_data["coverage"].values.map { |f| f["lines_covered_percent"] }
      formatted = pcts.map { |p| format("%.2f%%", (p * 100).floor / 100.0) }.sort_by(&:to_f)

      expect(formatted).to eq %w[
        57.14% 64.28% 66.66% 66.66% 80.00% 85.71%
        85.71% 85.71% 100.00% 100.00% 100.00% 100.00%
      ]
    end

    it "includes branch totals and per-file branch stats when branch coverage is enabled" do
      skip "Branch coverage not reliable on JRuby" if RUBY_ENGINE == "jruby"

      expect(coverage_data["total"]).to have_key("branches")
      coverage_data["coverage"].each_value do |file_data|
        expect(file_data).to include("branches", "branches_covered_percent")
      end
    end

    it "reports the expected per-file branch coverages" do
      skip "Branch coverage not reliable on JRuby" if RUBY_ENGINE == "jruby"

      pcts = coverage_data["coverage"].values.map { |f| f["branches_covered_percent"] }
      formatted = pcts.map { |p| format("%.2f%%", (p * 100).floor / 100.0) }.sort_by(&:to_f)

      expect(formatted).to eq %w[
        25.00% 25.00% 45.83% 50.00% 50.00% 50.00%
        60.00% 75.00% 100.00% 100.00% 100.00% 100.00%
      ]
    end

    it "includes source code arrays for every file" do
      coverage_data["coverage"].each_value do |file_data|
        expect(file_data).to include("source")
        expect(file_data["source"]).to be_a(Array)
        expect(file_data["source"]).not_to be_empty
      end
    end

    it "includes covered_lines / missed_lines counts for every file" do
      coverage_data["coverage"].each_value do |file_data|
        expect(file_data).to include("covered_lines", "missed_lines")
      end
    end

    it "writes the static index.html with the expected DOCTYPE and data-file reference" do
      html = File.read(File.join(coverage_dir, "index.html"))

      expect(html).to include("<!DOCTYPE html>")
      expect(html).to include("coverage_data.js")
    end
  end

  describe "method coverage" do
    before do
      skip "Method coverage not supported on this Ruby" unless SimpleCov.method_coverage_supported?

      SimpleCov.enable_coverage(:method)
      formatter.format(make_result)
    end

    after { SimpleCov.clear_coverage_criteria }

    it "reports a methods totals section" do
      expect(coverage_data["total"]).to have_key("methods")
    end

    it "sets the method_coverage meta flag" do
      expect(coverage_data["meta"]["method_coverage"]).to be true
    end
  end

  describe "with branch coverage explicitly disabled" do
    before do
      SimpleCov.clear_coverage_criteria
      formatter.format(make_result)
    end

    it "omits the branches section from totals" do
      expect(coverage_data["total"]).not_to have_key("branches")
    end

    it "sets the branch_coverage meta flag to false" do
      expect(coverage_data["meta"]["branch_coverage"]).to be_falsey
    end
  end
end
