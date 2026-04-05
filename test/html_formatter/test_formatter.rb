# frozen_string_literal: true

require "English"
require "helper"
require "coverage_fixtures"
require "tmpdir"
require "json"

class TestFormatter < Minitest::Test
  cover "SimpleCov::Formatter::HTMLFormatter#initialize" if respond_to?(:cover)

  def test_initialize_silent_default_false
    f = SimpleCov::Formatter::HTMLFormatter.new

    refute f.instance_variable_get(:@silent)
  end

  def test_initialize_silent_true
    f = SimpleCov::Formatter::HTMLFormatter.new(silent: true)

    assert f.instance_variable_get(:@silent)
  end

  cover "SimpleCov::Formatter::HTMLFormatter#format" if respond_to?(:cover)

  def test_format_writes_coverage_data_js
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      assert_path_exists File.join(dir, "coverage_data.js")
    end
  end

  def test_format_coverage_data_js_contains_valid_json
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      content = File.read(File.join(dir, "coverage_data.js"))

      assert content.start_with?("window.SIMPLECOV_DATA = ")
      assert content.end_with?(";\n")

      json_str = content.sub("window.SIMPLECOV_DATA = ", "").chomp(";\n")
      data = JSON.parse(json_str)

      assert_kind_of Hash, data
      assert data.key?("meta")
      assert data.key?("coverage")
      assert data.key?("total")
    end
  end

  def test_format_copies_index_html
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      assert_path_exists File.join(dir, "index.html")
    end
  end

  def test_format_copies_application_js
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      assert_path_exists File.join(dir, "application.js")
    end
  end

  def test_format_copies_application_css
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      assert_path_exists File.join(dir, "application.css")
    end
  end

  def test_format_copies_favicons
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      assert_path_exists File.join(dir, "favicon_green.png")
      assert_path_exists File.join(dir, "favicon_red.png")
      assert_path_exists File.join(dir, "favicon_yellow.png")
    end
  end

  def test_format_also_writes_coverage_json
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      assert_path_exists File.join(dir, "coverage.json")
    end
  end

  def test_format_prints_output_message_when_not_silent
    with_coverage_dir do
      f = SimpleCov::Formatter::HTMLFormatter.new(silent: false)
      stdout, = capture_io { f.format(make_result) }

      assert_includes stdout, "Coverage report generated"
    end
  end

  def test_format_does_not_print_when_silent
    with_coverage_dir do
      stdout, = capture_io { silent_formatter.format(make_result) }

      assert_empty stdout
    end
  end

  def test_format_writes_coverage_data_in_binary_mode
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      content = File.read(File.join(dir, "coverage_data.js"))

      assert content.start_with?("window.SIMPLECOV_DATA = ")
    end
  end

  def test_format_coverage_data_includes_source_code
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      data = parse_coverage_data(dir)
      file_data = data["coverage"].values.first

      assert file_data.key?("source"), "Expected source code in coverage data"
      assert_kind_of Array, file_data["source"]
      refute_empty file_data["source"]
    end
  end

  def test_format_coverage_data_includes_meta
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      data = parse_coverage_data(dir)
      meta = data["meta"]

      assert meta.key?("simplecov_version")
      assert meta.key?("command_name")
      assert meta.key?("project_name")
      assert meta.key?("timestamp")
      assert meta.key?("root")
      assert [true, false].include?(meta["branch_coverage"])
      assert [true, false].include?(meta["method_coverage"])
    end
  end

  cover "SimpleCov::Formatter::HTMLFormatter#format_from_json" if respond_to?(:cover)

  def test_format_from_json_writes_coverage_data_js
    with_coverage_dir do |dir|
      # First generate coverage.json
      silent_formatter.format(make_result)

      # Now use format_from_json to generate in a different directory
      output_dir = File.join(dir, "standalone")
      json_path = File.join(dir, "coverage.json")
      SimpleCov::Formatter::HTMLFormatter.new.format_from_json(json_path, output_dir)

      assert_path_exists File.join(output_dir, "coverage_data.js")
      assert_path_exists File.join(output_dir, "index.html")
      assert_path_exists File.join(output_dir, "application.js")
    end
  end

  def test_format_from_json_produces_valid_data
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)

      output_dir = File.join(dir, "standalone")
      json_path = File.join(dir, "coverage.json")
      SimpleCov::Formatter::HTMLFormatter.new.format_from_json(json_path, output_dir)

      data = parse_coverage_data(output_dir)

      assert data.key?("meta")
      assert data.key?("coverage")
    end
  end

  cover "SimpleCov::Formatter::HTMLFormatter#output_message" if respond_to?(:cover)

  def test_output_message_includes_command_name
    with_coverage_dir do
      f = SimpleCov::Formatter::HTMLFormatter.new(silent: false)
      stdout, = capture_io { f.format(make_result) }

      assert_includes stdout, "Coverage report generated"
    end
  end

  def test_output_message_includes_loc_stats
    with_coverage_dir do
      f = SimpleCov::Formatter::HTMLFormatter.new(silent: false)
      stdout, = capture_io { f.format(make_result) }

      assert_match(/\d+ \/ \d+ LOC/, stdout)
    end
  end

private

  def make_result
    SimpleCov::Result.new({fixtures_path.join("sample.rb").to_s => CoverageFixtures::SAMPLE_RB})
  end

  def fixtures_path
    Pathname.new(__dir__).join("fixtures")
  end

  def silent_formatter
    SimpleCov::Formatter::HTMLFormatter.new(silent: true)
  end

  def parse_coverage_data(dir)
    content = File.read(File.join(dir, "coverage_data.js"))
    json_str = content.sub("window.SIMPLECOV_DATA = ", "").chomp(";\n")
    JSON.parse(json_str)
  end

  def with_coverage_dir
    dir = File.join(Dir.tmpdir, "simplecov_test_#{$PROCESS_ID}_#{rand(10_000)}")
    FileUtils.mkdir_p(dir)
    original_dir = SimpleCov.coverage_dir
    SimpleCov.coverage_dir(dir)
    yield dir
  ensure
    SimpleCov.coverage_dir(original_dir)
    FileUtils.rm_rf(dir)
  end
end
