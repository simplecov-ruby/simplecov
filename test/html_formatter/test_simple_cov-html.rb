# frozen_string_literal: true

require "helper"
require "coverage_fixtures"
require "json"

class TestSimpleCovHtml < Minitest::Test
  def setup
    @original_coverage_dir = SimpleCov.coverage_dir
    @original_criteria = SimpleCov.coverage_criteria.dup
    @original_filters = SimpleCov.filters.dup
    SimpleCov.coverage_dir(output_path)
    SimpleCov.enable_coverage(:branch)
    SimpleCov.filters.clear
  end

  def teardown
    SimpleCov.coverage_dir(@original_coverage_dir)
    SimpleCov.clear_coverage_criteria
    @original_criteria.each { |criterion| SimpleCov.enable_coverage(criterion) }
    SimpleCov.filters.replace(@original_filters)
  end

  def test_data_filename_constant
    assert_equal "coverage_data.js", SimpleCov::Formatter::HTMLFormatter::DATA_FILENAME
  end

  def test_total_line_coverage_percent
    data = format_results(CoverageFixtures::ALL_FIXTURES)

    assert_in_delta 72.94, data["total"]["lines"]["percent"], 0.01
  end

  def test_per_file_line_coverages
    data = format_results(CoverageFixtures::ALL_FIXTURES)

    pcts = data["coverage"].values.map { |f| f["lines_covered_percent"] }
    formatted = pcts.map { |p| format("%.2f%%", (p * 100).floor / 100.0) }.sort_by(&:to_f)

    expected = %w[
      57.14% 64.28% 66.66% 66.66% 80.00% 80.00%
      85.71% 85.71% 85.71% 100.00% 100.00% 100.00%
    ]

    assert_equal expected, formatted
  end

  def test_branch_coverage_included_when_enabled
    skip "Branch coverage not reliable on JRuby" if RUBY_ENGINE == "jruby"

    data = format_results(CoverageFixtures::ALL_FIXTURES)

    assert data["total"].key?("branches"), "Expected branch coverage in totals"
    data["coverage"].each_value do |file_data|
      assert file_data.key?("branches"), "Expected branches in file data"
      assert file_data.key?("branches_covered_percent"), "Expected branches_covered_percent in file data"
    end
  end

  def test_per_file_branch_coverages
    skip "Branch coverage not reliable on JRuby" if RUBY_ENGINE == "jruby"

    data = format_results(CoverageFixtures::ALL_FIXTURES)

    pcts = data["coverage"].values.map { |f| f["branches_covered_percent"] }
    formatted = pcts.map { |p| format("%.2f%%", (p * 100).floor / 100.0) }.sort_by(&:to_f)

    expected = %w[
      25.00% 25.00% 45.83% 50.00% 50.00% 50.00%
      60.00% 66.66% 100.00% 100.00% 100.00% 100.00%
    ]

    assert_equal expected, formatted
  end

  def test_source_code_included
    data = format_results(CoverageFixtures::ALL_FIXTURES)

    data["coverage"].each_value do |file_data|
      assert file_data.key?("source"), "Expected source code in file data"
      assert_kind_of Array, file_data["source"]
      refute_empty file_data["source"]
    end
  end

  def test_coverage_counts_included
    data = format_results(CoverageFixtures::ALL_FIXTURES)

    data["coverage"].each_value do |file_data|
      assert file_data.key?("covered_lines"), "Expected covered_lines"
      assert file_data.key?("missed_lines"), "Expected missed_lines"
    end
  end

  def test_method_coverage_included_when_enabled
    skip "Method coverage not supported" unless SimpleCov.method_coverage_supported?

    SimpleCov.enable_coverage(:method)
    data = format_results("sample.rb" => CoverageFixtures::SAMPLE_RB)

    assert data["total"].key?("methods"), "Expected methods in totals"
    assert data["meta"]["method_coverage"], "Expected method_coverage flag to be true"
  end

  def test_no_branch_coverage_when_disabled
    SimpleCov.clear_coverage_criteria
    data = format_results("sample.rb" => CoverageFixtures::SAMPLE_RB)

    refute data["total"].key?("branches"), "Expected no branch coverage in totals"
    refute data["meta"]["branch_coverage"], "Expected branch_coverage flag to be false"
  end

  def test_silenced_output
    result = SimpleCov::Result.new({fixtures_path.join("sample.rb").to_s => CoverageFixtures::SAMPLE_RB})
    stdout, = capture_io { SimpleCov::Formatter::HTMLFormatter.new(silent: true).format(result) }

    assert_empty stdout
  end

  def test_static_index_html_copied
    format_results("sample.rb" => CoverageFixtures::SAMPLE_RB)

    assert_path_exists output_path.join("index.html").to_s
    html = output_path.join("index.html").read

    assert_includes html, "<!DOCTYPE html>"
    assert_includes html, "coverage_data.js"
  end

  def test_meta_includes_required_fields
    data = format_results("sample.rb" => CoverageFixtures::SAMPLE_RB)
    meta = data["meta"]

    assert meta.key?("simplecov_version")
    assert meta.key?("command_name")
    assert meta.key?("project_name")
    assert meta.key?("timestamp")
    assert meta.key?("root")
  end

private

  def format_results(coverage_results)
    coverage_results = coverage_results.transform_keys { |name| fixtures_path.join(name).to_s }
    result = SimpleCov::Result.new(coverage_results)
    capture_io { SimpleCov::Formatter::HTMLFormatter.new.format(result) }
    parse_coverage_data
  end

  def parse_coverage_data
    content = output_path.join("coverage_data.js").read
    json_str = content.sub("window.SIMPLECOV_DATA = ", "").chomp(";\n")
    JSON.parse(json_str)
  end

  def output_path
    Pathname.new(__dir__).parent.join("tmp", "test_output")
  end

  def fixtures_path
    Pathname.new(__dir__).join("fixtures")
  end
end
