# frozen_string_literal: true

require "helper"
require "coverage_fixtures"

class TestSimpleCovHtml < Minitest::Test
  EXPECTED_LINE_COVERAGES = %w[
    57.14% 64.28% 66.66% 66.66% 80.00% 80.00%
    85.71% 85.71% 85.71% 100.00% 100.00% 100.00%
  ].freeze

  EXPECTED_BRANCH_COVERAGES = %w[
    25.00% 25.00% 45.83% 50.00% 50.00% 50.00%
    60.00% 66.66% 100.00% 100.00% 100.00% 100.00%
  ].freeze

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

  def test_version_defined
    assert_predicate SimpleCov::Formatter::HTMLFormatter::VERSION, :frozen?
  end

  def test_output_header_coverage
    html_doc = format_results(CoverageFixtures::ALL_FIXTURES)
    header = html_doc.at_css("div#AllFiles span.covered_percent span").content.strip

    assert_equal "72.94%", header
  end

  def test_output_line_coverages
    html_doc = format_results(CoverageFixtures::ALL_FIXTURES)
    pcts = html_doc.css("div#AllFiles table.file_list tr.t-file .cell--line-pct")
    table = pcts.map { |m| m.content.strip }

    assert_equal EXPECTED_LINE_COVERAGES, table.sort_by(&:to_f)
  end

  def test_output_branch_coverages
    skip "Branch coverage not reliable on JRuby" if RUBY_ENGINE == "jruby"

    html_doc = format_results(CoverageFixtures::ALL_FIXTURES)

    branch_pct = html_doc.at_css("div#AllFiles td.t-totals__branch-pct")

    assert branch_pct, "Expected branch coverage totals row"

    pcts = html_doc.css("div#AllFiles table.file_list tr.t-file .cell--branch-pct")
    table = pcts.map { |m| m.content.strip }

    assert_equal EXPECTED_BRANCH_COVERAGES, table.sort_by(&:to_f)
  end

  def test_coverage_cells_contain_bar_and_percentage
    html_doc = format_results(CoverageFixtures::ALL_FIXTURES)
    cov_cells = html_doc.css("div#AllFiles table.file_list tbody td.cell--coverage")

    assert_operator cov_cells.length, :>=, 1, "Expected at least one coverage cell"
    cov_cells.each do |td|
      assert td.at_css(".bar-sizer"), "Coverage cell must contain a bar-sizer"
      assert td.at_css(".coverage-pct"), "Coverage cell must contain a coverage-pct"
    end
  end

  def test_line_pct_cells_have_data_order
    html_doc = format_results(CoverageFixtures::ALL_FIXTURES)
    pct_cells = html_doc.css("div#AllFiles table.file_list tbody td.cell--line-pct")

    assert_equal 12, pct_cells.length
    pct_cells.each do |td|
      order = td["data-order"]

      assert order, "Each line pct cell must have a data-order attribute"
      assert_match(/\A\d+\.\d+\z/, order, "data-order must be a decimal number, got '#{order}'")
    end
  end

  def test_branch_pct_cells_have_data_order
    skip "Branch coverage not reliable on JRuby" if RUBY_ENGINE == "jruby"

    html_doc = format_results(CoverageFixtures::ALL_FIXTURES)
    pct_cells = html_doc.css("div#AllFiles table.file_list tbody td.cell--branch-pct")

    assert_operator pct_cells.length, :>=, 1, "Expected at least one branch pct cell"
    pct_cells.each do |td|
      order = td["data-order"]

      assert order, "Each branch pct cell must have a data-order attribute"
      assert_match(/\A\d+\.\d+\z/, order, "data-order must be a decimal number, got '#{order}'")
    end
  end

  def test_output_with_method_coverage
    skip "Method coverage not supported" unless SimpleCov.method_coverage_supported?

    SimpleCov.enable_coverage(:method)
    html_doc = format_results("sample.rb" => CoverageFixtures::SAMPLE_RB)

    assert html_doc.at_css("div#AllFiles td.t-totals__method-pct"),
           "Expected method coverage totals row"
  end

  def test_output_without_branch_coverage
    SimpleCov.clear_coverage_criteria
    html_doc = format_results("sample.rb" => CoverageFixtures::SAMPLE_RB)

    assert_nil html_doc.at_css("div#AllFiles td.t-totals__branch-coverage")

    stdout, = capture_io { format_results("sample.rb" => CoverageFixtures::SAMPLE_RB) }

    refute_match(/Branch coverage:.*%/, stdout)
  end

  def test_inline_assets
    FileUtils.rm_rf(output_path)
    ENV["SIMPLECOV_INLINE_ASSETS"] = "true"
    html = generate_inline_html

    assert_match(%r{data:text/javascript;base64,}, html)
    assert_match(%r{data:text/css;base64,}, html)
    refute_path_exists output_path.join("assets").to_s
  ensure
    ENV.delete("SIMPLECOV_INLINE_ASSETS")
    FileUtils.rm_rf(output_path)
  end

  def test_encoding_error_handling
    formatter = SimpleCov::Formatter::HTMLFormatter.new
    bad_template = Object.new
    def bad_template.result(_binding)
      raise Encoding::CompatibilityError, "incompatible encoding"
    end
    formatter.instance_variable_get(:@templates)["source_file"] = bad_template

    source_file = SimpleCov::SourceFile.new(fixtures_path.join("sample.rb").to_s, CoverageFixtures::SAMPLE_RB)
    output, = capture_io { formatter.send(:formatted_source_file, source_file) }

    assert_match(/Encoding problems with file/, output)
  end

  def test_silenced_output
    result = SimpleCov::Result.new({fixtures_path.join("sample.rb").to_s => CoverageFixtures::SAMPLE_RB})
    stdout, = capture_io { SimpleCov::Formatter::HTMLFormatter.new(silent: true).format(result) }

    assert_empty stdout
  end

private

  def generate_inline_html
    formatter = SimpleCov::Formatter::HTMLFormatter.new
    result = SimpleCov::Result.new({fixtures_path.join("sample.rb").to_s => CoverageFixtures::SAMPLE_RB})
    capture_io { formatter.format(result) }
    output_path.join("index.html").read
  end

  def format_results(coverage_results)
    coverage_results = coverage_results.transform_keys { |name| fixtures_path.join(name).to_s }
    result = SimpleCov::Result.new(coverage_results)
    capture_io { SimpleCov::Formatter::HTMLFormatter.new.format(result) }
    output_path.join("index.html").open { |f| Nokogiri::HTML(f) }
  end

  def output_path
    Pathname.new(__dir__).parent.join("tmp", "test_output")
  end

  def fixtures_path
    Pathname.new(__dir__).join("fixtures")
  end
end
