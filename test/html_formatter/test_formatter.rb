# frozen_string_literal: true

require "English"
require "helper"
require "coverage_fixtures"
require "tmpdir"

class TestFormatter < Minitest::Test
  cover "SimpleCov::Formatter::HTMLFormatter#initialize" if respond_to?(:cover)

  def test_initialize_sets_branch_coverage_from_simplecov
    f = SimpleCov::Formatter::HTMLFormatter.new

    assert_equal SimpleCov.branch_coverage?, f.instance_variable_get(:@branch_coverage)
  end

  def test_initialize_branch_coverage_false_when_disabled
    with_coverage_criteria_cleared do
      f = SimpleCov::Formatter::HTMLFormatter.new

      refute f.instance_variable_get(:@branch_coverage)
    end
  end

  def test_initialize_branch_coverage_true_when_enabled
    skip "Branch coverage not supported on JRuby" if RUBY_ENGINE == "jruby"

    with_coverage_criteria_cleared do
      SimpleCov.enable_coverage(:branch)
      f = SimpleCov::Formatter::HTMLFormatter.new

      assert f.instance_variable_get(:@branch_coverage)
    end
  end

  def test_initialize_sets_method_coverage_based_on_simplecov
    f = SimpleCov::Formatter::HTMLFormatter.new

    assert_equal SimpleCov.method_coverage?, f.instance_variable_get(:@method_coverage)
  end

  def test_initialize_sets_method_coverage_false_when_disabled
    with_coverage_criteria_cleared do
      f = SimpleCov::Formatter::HTMLFormatter.new

      refute f.instance_variable_get(:@method_coverage)
    end
  end

  def test_initialize_sets_method_coverage_true_when_enabled
    skip "Method coverage not supported" unless SimpleCov.respond_to?(:method_coverage_supported?) && SimpleCov.method_coverage_supported?
    with_coverage_criteria_cleared do
      SimpleCov.enable_coverage(:method)
      f = SimpleCov::Formatter::HTMLFormatter.new

      assert f.instance_variable_get(:@method_coverage)
    end
  end

  def test_initialize_method_coverage_reflects_simplecov
    f = SimpleCov::Formatter::HTMLFormatter.new
    expected = SimpleCov.respond_to?(:method_coverage?) && SimpleCov.method_coverage?

    assert_equal expected, f.instance_variable_get(:@method_coverage)
  end

  def test_initialize_creates_empty_templates_hash
    f = SimpleCov::Formatter::HTMLFormatter.new

    assert_equal({}, f.instance_variable_get(:@templates))
  end

  def test_initialize_inline_assets_default_false
    ENV.delete("SIMPLECOV_INLINE_ASSETS")
    f = SimpleCov::Formatter::HTMLFormatter.new

    refute f.instance_variable_get(:@inline_assets)
  end

  def test_initialize_inline_assets_from_kwarg
    f = SimpleCov::Formatter::HTMLFormatter.new(inline_assets: true)

    assert f.instance_variable_get(:@inline_assets)
  end

  def test_initialize_inline_assets_from_env
    ENV["SIMPLECOV_INLINE_ASSETS"] = "1"
    f = SimpleCov::Formatter::HTMLFormatter.new

    assert f.instance_variable_get(:@inline_assets)
  ensure
    ENV.delete("SIMPLECOV_INLINE_ASSETS")
  end

  def test_initialize_silent_default_false
    f = SimpleCov::Formatter::HTMLFormatter.new

    refute f.instance_variable_get(:@silent)
  end

  def test_initialize_silent_true
    f = SimpleCov::Formatter::HTMLFormatter.new(silent: true)

    assert f.instance_variable_get(:@silent)
  end

  def test_initialize_public_assets_dir_points_to_public
    f = SimpleCov::Formatter::HTMLFormatter.new
    dir = f.instance_variable_get(:@public_assets_dir)

    assert dir.end_with?("/public/"), "Expected public/ dir, got: #{dir}"
    assert File.directory?(dir), "Expected #{dir} to exist"
  end

  cover "SimpleCov::Formatter::HTMLFormatter#format" if respond_to?(:cover)

  def test_format_writes_index_html
    with_coverage_dir do |dir|
      f = silent_formatter
      f.format(make_result)
      html = File.read(File.join(dir, "index.html"))

      assert_includes html, "<!DOCTYPE html>"
    end
  end

  def test_format_copies_assets_when_not_inline
    with_coverage_dir do |dir|
      silent_formatter.format(make_result)
      asset_dir = versioned_asset_dir(dir)

      assert File.directory?(asset_dir), "Expected assets directory at #{asset_dir}"
      assert_path_exists File.join(asset_dir, "application.js")
      assert_path_exists File.join(asset_dir, "application.css")
    end
  end

  def test_format_does_not_copy_assets_when_inline
    with_coverage_dir do |dir|
      f = SimpleCov::Formatter::HTMLFormatter.new(silent: true, inline_assets: true)
      f.format(make_result)

      refute File.directory?(File.join(dir, "assets")), "Expected no assets directory when inline"
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

  def test_format_writes_in_binary_mode
    with_coverage_dir do |_dir|
      write_calls = spy_on_file_write do
        silent_formatter.format(make_result)
      end

      assert_equal [{mode: "wb"}], write_calls
    end
  end

  def test_format_copies_assets_with_remove_destination
    with_coverage_dir do |_dir|
      cp_r_calls = spy_on_cp_r do
        silent_formatter.format(make_result)
      end

      refute_empty cp_r_calls, "Expected at least one cp_r call"
      cp_r_calls.each do |opts|
        assert opts[:remove_destination], "Expected remove_destination: true, got #{opts.inspect}"
      end
    end
  end

  cover "SimpleCov::Formatter::HTMLFormatter#output_message" if respond_to?(:cover)

  def test_output_message_includes_command_name
    msg = output_message_for("RSpec", line: stat(80, 100), branch: stat(10, 20))

    assert_includes msg, "RSpec"
  end

  def test_output_message_includes_output_path
    msg = output_message_for("Test", line: stat(80, 100), branch: stat(10, 20))

    assert_includes msg, SimpleCov.coverage_path
  end

  def test_output_message_includes_line_coverage
    msg = output_message_for("Test", line: stat(80, 100), branch: stat(10, 20))

    assert_includes msg, "Line coverage:"
    assert_includes msg, "80 / 100"
  end

  def test_output_message_includes_branch_coverage_when_enabled
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.instance_variable_set(:@branch_coverage, true)
    stats = {line: stat(80, 100), branch: stat(15, 20)}
    stats[:method] = stat(0, 0) if f.instance_variable_get(:@method_coverage)
    msg = f.send(:output_message, stub_result("Test", stats))

    assert_includes msg, "Branch coverage:"
    assert_includes msg, "15 / 20"
  end

  def test_output_message_excludes_branch_coverage_when_disabled
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.instance_variable_set(:@branch_coverage, false)
    stats = {line: stat(80, 100)}
    stats[:method] = stat(0, 0) if f.instance_variable_get(:@method_coverage)
    msg = f.send(:output_message, stub_result("Test", stats))

    refute_includes msg, "Branch coverage:"
  end

  def test_output_message_includes_method_coverage_when_enabled
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.instance_variable_set(:@method_coverage, true)
    f.instance_variable_set(:@branch_coverage, false)
    msg = f.send(:output_message, stub_result("Test", line: stat(80, 100), method: stat(5, 10)))

    assert_includes msg, "Method coverage:"
    assert_includes msg, "5 / 10"
  end

  def test_output_message_excludes_method_coverage_when_disabled
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.instance_variable_set(:@method_coverage, false)
    f.instance_variable_set(:@branch_coverage, false)
    msg = f.send(:output_message, stub_result("Test", line: stat(80, 100)))

    refute_includes msg, "Method coverage:"
  end

  def test_output_message_starts_with_coverage_report_generated
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.instance_variable_set(:@branch_coverage, false)
    f.instance_variable_set(:@method_coverage, false)
    msg = f.send(:output_message, stub_result("MyTest", line: stat(50, 50)))

    assert msg.start_with?("Coverage report generated for MyTest to ")
  end

  def test_output_message_lines_are_joined_with_newlines
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.instance_variable_set(:@branch_coverage, true)
    f.instance_variable_set(:@method_coverage, true)
    result = stub_result("Test", line: stat(80, 100), branch: stat(10, 20), method: stat(5, 10))
    lines = f.send(:output_message, result).split("\n")

    assert_equal 4, lines.length
  end

  cover "SimpleCov::Formatter::HTMLFormatter#template" if respond_to?(:cover)

  def test_template_returns_erb_object
    f = SimpleCov::Formatter::HTMLFormatter.new

    assert_instance_of ERB, f.send(:template, "layout")
  end

  def test_template_caches_result
    f = SimpleCov::Formatter::HTMLFormatter.new
    tmpl1 = f.send(:template, "layout")
    tmpl2 = f.send(:template, "layout")

    assert_same tmpl1, tmpl2
  end

  def test_template_loads_different_templates
    f = SimpleCov::Formatter::HTMLFormatter.new
    layout = f.send(:template, "layout")
    file_list = f.send(:template, "file_list")

    refute_same layout, file_list
  end

  def test_template_stores_in_templates_hash
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.send(:template, "layout")
    templates = f.instance_variable_get(:@templates)

    assert templates.key?("layout")
    assert_instance_of ERB, templates["layout"]
  end

  def test_template_reads_from_views_directory
    f = SimpleCov::Formatter::HTMLFormatter.new
    tmpl = f.send(:template, "covered_percent")

    refute_nil tmpl
    assert_instance_of ERB, tmpl
  end

  cover "SimpleCov::Formatter::HTMLFormatter#output_path" if respond_to?(:cover)

  def test_output_path_delegates_to_simplecov_coverage_path
    f = SimpleCov::Formatter::HTMLFormatter.new

    assert_equal SimpleCov.coverage_path, f.send(:output_path)
  end

  def test_output_path_returns_string
    f = SimpleCov::Formatter::HTMLFormatter.new

    assert_kind_of String, f.send(:output_path)
  end

  cover "SimpleCov::Formatter::HTMLFormatter#asset_output_path" if respond_to?(:cover)

  def test_asset_output_path_creates_directory
    with_coverage_dir do |_dir|
      f = SimpleCov::Formatter::HTMLFormatter.new

      assert File.directory?(f.send(:asset_output_path)), "Expected directory to exist"
    end
  end

  def test_asset_output_path_includes_version
    with_coverage_dir do
      path = SimpleCov::Formatter::HTMLFormatter.new.send(:asset_output_path)

      assert_includes path, SimpleCov::Formatter::HTMLFormatter::VERSION
    end
  end

  def test_asset_output_path_includes_assets_subdir
    with_coverage_dir do
      path = SimpleCov::Formatter::HTMLFormatter.new.send(:asset_output_path)

      assert_includes path, "/assets/"
    end
  end

  def test_asset_output_path_is_cached
    with_coverage_dir do
      f = SimpleCov::Formatter::HTMLFormatter.new
      path1 = f.send(:asset_output_path)
      path2 = f.send(:asset_output_path)

      assert_same path1, path2
    end
  end

  def test_asset_output_path_is_under_output_path
    with_coverage_dir do |dir|
      path = SimpleCov::Formatter::HTMLFormatter.new.send(:asset_output_path)

      assert path.start_with?(dir), "Expected #{path} to start with #{dir}"
    end
  end

  def test_asset_output_path_joins_output_path_assets_version
    with_coverage_dir do |dir|
      expected = File.join(dir, "assets", SimpleCov::Formatter::HTMLFormatter::VERSION)

      assert_equal expected, SimpleCov::Formatter::HTMLFormatter.new.send(:asset_output_path)
    end
  end

  cover "SimpleCov::Formatter::HTMLFormatter#assets_path" if respond_to?(:cover)

  def test_assets_path_returns_relative_path_when_not_inline
    f = SimpleCov::Formatter::HTMLFormatter.new(inline_assets: false)
    ENV.delete("SIMPLECOV_INLINE_ASSETS")
    expected = File.join("./assets", SimpleCov::Formatter::HTMLFormatter::VERSION, "application.js")

    assert_equal expected, f.send(:assets_path, "application.js")
  end

  def test_assets_path_includes_version
    f = SimpleCov::Formatter::HTMLFormatter.new(inline_assets: false)
    ENV.delete("SIMPLECOV_INLINE_ASSETS")

    assert_includes f.send(:assets_path, "application.css"), SimpleCov::Formatter::HTMLFormatter::VERSION
  end

  def test_assets_path_returns_data_uri_when_inline
    f = SimpleCov::Formatter::HTMLFormatter.new(inline_assets: true)
    result = f.send(:assets_path, "application.js")

    assert result.start_with?("data:"), "Expected data URI, got: #{result[0..30]}"
  end

  def test_assets_path_starts_with_dot_slash_assets_when_not_inline
    f = SimpleCov::Formatter::HTMLFormatter.new(inline_assets: false)
    ENV.delete("SIMPLECOV_INLINE_ASSETS")
    result = f.send(:assets_path, "application.css")

    assert result.start_with?("./assets/"), "Expected ./assets/ prefix, got: #{result}"
  end

  cover "SimpleCov::Formatter::HTMLFormatter#asset_inline" if respond_to?(:cover)

  def test_asset_inline_returns_data_uri_for_js
    result = SimpleCov::Formatter::HTMLFormatter.new.send(:asset_inline, "application.js")

    assert result.start_with?("data:text/javascript;base64,")
  end

  def test_asset_inline_returns_data_uri_for_css
    result = SimpleCov::Formatter::HTMLFormatter.new.send(:asset_inline, "application.css")

    assert result.start_with?("data:text/css;base64,")
  end

  def test_asset_inline_returns_data_uri_for_png
    result = SimpleCov::Formatter::HTMLFormatter.new.send(:asset_inline, "favicon_green.png")

    assert result.start_with?("data:image/png;base64,")
  end

  def test_asset_inline_encodes_content_as_base64
    f = SimpleCov::Formatter::HTMLFormatter.new
    result = f.send(:asset_inline, "application.js")
    decoded = result.sub("data:text/javascript;base64,", "").unpack1("m0")
    public_dir = f.instance_variable_get(:@public_assets_dir)

    assert_equal File.read(File.join(public_dir, "application.js")), decoded
  end

  def test_asset_inline_uses_m0_pack_no_newlines
    result = SimpleCov::Formatter::HTMLFormatter.new.send(:asset_inline, "application.js")
    base64_part = result.sub("data:text/javascript;base64,", "")

    refute_includes base64_part, "\n"
  end

  def test_asset_inline_uses_correct_content_type_from_extension
    f = SimpleCov::Formatter::HTMLFormatter.new
    js_result = f.send(:asset_inline, "application.js")
    css_result = f.send(:asset_inline, "application.css")

    assert_includes js_result, "text/javascript"
    assert_includes css_result, "text/css"
    refute_includes js_result, "text/css"
    refute_includes css_result, "text/javascript"
  end

  def test_asset_inline_reads_from_public_assets_dir
    f = SimpleCov::Formatter::HTMLFormatter.new
    public_dir = f.instance_variable_get(:@public_assets_dir)
    expected_base64 = [File.read(File.join(public_dir, "application.css"))].pack("m0")

    assert_equal "data:text/css;base64,#{expected_base64}", f.send(:asset_inline, "application.css")
  end

  cover "SimpleCov::Formatter::HTMLFormatter#formatted_source_file" if respond_to?(:cover)

  def test_formatted_source_file_returns_html
    with_coverage_dir do
      f = SimpleCov::Formatter::HTMLFormatter.new
      result = f.send(:formatted_source_file, sample_source_file)

      assert_includes result, "source_table"
      assert_includes result, "Foo"
    end
  end

  def test_formatted_source_file_uses_source_file_template
    with_coverage_dir do
      f = SimpleCov::Formatter::HTMLFormatter.new
      result = f.send(:formatted_source_file, sample_source_file)

      assert_includes result, shortened_name("sample.rb")
    end
  end

  def test_formatted_source_file_handles_encoding_error
    f = formatter_with_bad_template("bad encoding")
    stdout, = capture_io { f.send(:formatted_source_file, sample_source_file) }

    assert_includes stdout, "Encoding problems with file"
    assert_includes stdout, sample_source_file.filename
  end

  def test_formatted_source_file_encoding_error_prints_error_message
    error = Encoding::CompatibilityError.new("incompatible character")
    error.define_singleton_method(:message) { "the_real_message" }
    f = formatter_with_bad_template_error(error)
    stdout, = capture_io { f.send(:formatted_source_file, sample_source_file) }

    assert_includes stdout, "the_real_message"
    refute_includes stdout, "incompatible character"
  end

  def test_formatted_source_file_encoding_error_returns_placeholder
    f = formatter_with_bad_template("bad")
    capture_io { @encoding_result = f.send(:formatted_source_file, sample_source_file) }

    assert_includes @encoding_result, "source_table"
    assert_includes @encoding_result, "Encoding Error"
  end

  def test_formatted_source_file_encoding_error_contains_correct_id
    f = formatter_with_bad_template("bad")
    result = nil
    capture_io { result = f.send(:formatted_source_file, sample_source_file) }
    expected_id = Digest::MD5.hexdigest(sample_source_file.filename)

    assert_includes result, %(id="#{expected_id}")
  end

  def test_formatted_source_file_encoding_error_html_escapes_message
    error = Encoding::CompatibilityError.new("dummy")
    error.define_singleton_method(:message) { "<script>alert('xss')</script>" }
    f = formatter_with_bad_template_error(error)
    result = nil
    capture_io { result = f.send(:formatted_source_file, sample_source_file) }

    assert_includes result, ERB::Util.html_escape("<script>alert('xss')</script>")
    refute_includes result, "<script>alert"
  end

  def test_formatted_source_file_encoding_error_message_in_paragraph
    error = Encoding::CompatibilityError.new("dummy")
    error.define_singleton_method(:message) { "specific_error_text_42" }
    f = formatter_with_bad_template_error(error)
    result = nil
    capture_io { result = f.send(:formatted_source_file, sample_source_file) }

    assert_includes result, "<p>specific_error_text_42</p>"
  end

  cover "SimpleCov::Formatter::HTMLFormatter#formatted_file_list" if respond_to?(:cover)

  def test_formatted_file_list_returns_html_with_title
    with_coverage_dir do
      result = format_file_list("All Files")

      assert_includes result, "All Files"
    end
  end

  def test_formatted_file_list_contains_file_list_container
    with_coverage_dir do
      result = format_file_list("All Files")

      assert_includes result, "file_list_container"
    end
  end

  def test_formatted_file_list_uses_file_list_template
    with_coverage_dir do
      result = format_file_list("My Group")

      assert_includes result, "My Group"
      assert_includes result, "file_list"
    end
  end

  cover "SimpleCov::Formatter::HTMLFormatter#render_stats" if respond_to?(:cover)

  def test_render_stats_formats_line_coverage
    output = render_stats_for(line: stat(80, 100), type: :line)

    assert_equal "80 / 100 (80.00%)", output
  end

  def test_render_stats_formats_branch_coverage
    output = render_stats_for(branch: stat(15, 20), type: :branch)

    assert_equal "15 / 20 (75.00%)", output
  end

  def test_render_stats_formats_zero_total
    output = render_stats_for(line: stat(0, 0, 100.0), type: :line)

    assert_equal "0 / 0 (100.00%)", output
  end

  def test_render_stats_formats_full_coverage
    output = render_stats_for(line: stat(50, 50, 100.0), type: :line)

    assert_equal "50 / 50 (100.00%)", output
  end

  def test_render_stats_formats_with_two_decimal_places
    output = render_stats_for(line: stat(1, 3, 33.33), type: :line)

    assert_equal "1 / 3 (33.33%)", output
  end

  def test_render_stats_uses_fetch_on_coverage_statistics
    output = render_stats_for(line: stat(80, 100), type: :line)

    assert_includes output, "80"
    assert_includes output, "100"
    assert_includes output, "80.00%"
  end

private

  def stat(covered, total, percent = nil)
    pct = percent || (total.positive? ? (covered * 100.0 / total) : 100.0)
    obj = Object.new
    obj.define_singleton_method(:covered) { covered }
    obj.define_singleton_method(:total) { total }
    obj.define_singleton_method(:percent) { pct }
    obj
  end

  def stub_result(command_name, stats = {})
    coverage_statistics = {}
    stats.each { |k, v| coverage_statistics[k] = v }
    obj = Object.new
    obj.define_singleton_method(:command_name) { command_name }
    obj.define_singleton_method(:coverage_statistics) { coverage_statistics }
    obj
  end

  def fixtures_path
    Pathname.new(__dir__).join("fixtures")
  end

  def make_source_file(name, coverage_data)
    SimpleCov::SourceFile.new(fixtures_path.join(name).to_s, coverage_data)
  end

  def make_source_files
    files = [make_source_file("sample.rb", CoverageFixtures::SAMPLE_RB)]
    SimpleCov::FileList.new(files)
  end

  def make_result
    SimpleCov::Result.new({fixtures_path.join("sample.rb").to_s => CoverageFixtures::SAMPLE_RB})
  end

  def shortened_name(fixture_name)
    fixtures_path.join(fixture_name).to_s.sub(SimpleCov.root, ".").delete_prefix("./")
  end

  def sample_source_file
    @sample_source_file ||= make_source_file("sample.rb", CoverageFixtures::SAMPLE_RB)
  end

  def silent_formatter
    SimpleCov::Formatter::HTMLFormatter.new(silent: true)
  end

  def versioned_asset_dir(dir)
    File.join(dir, "assets", SimpleCov::Formatter::HTMLFormatter::VERSION)
  end

  def output_message_for(command, stats = {})
    f = SimpleCov::Formatter::HTMLFormatter.new
    # Ensure method stats present when method_coverage is enabled
    stats[:method] ||= stat(0, 0) if f.instance_variable_get(:@method_coverage)
    f.send(:output_message, stub_result(command, stats))
  end

  def render_stats_for(type:, **stats)
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.send(:render_stats, stub_result("Test", stats), type)
  end

  def format_file_list(title)
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.send(:formatted_file_list, title, make_source_files)
  end

  def formatter_with_bad_template(message)
    f = SimpleCov::Formatter::HTMLFormatter.new
    bad_template = Object.new
    bad_template.define_singleton_method(:result) { |_b| raise Encoding::CompatibilityError, message }
    f.instance_variable_get(:@templates)["source_file"] = bad_template
    f
  end

  def formatter_with_bad_template_error(error)
    f = SimpleCov::Formatter::HTMLFormatter.new
    bad_template = Object.new
    bad_template.define_singleton_method(:result) { |_b| raise error }
    f.instance_variable_get(:@templates)["source_file"] = bad_template
    f
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

  def with_coverage_criteria_cleared
    original_criteria = SimpleCov.coverage_criteria.dup
    SimpleCov.clear_coverage_criteria
    yield
  ensure
    SimpleCov.clear_coverage_criteria
    original_criteria.each { |criterion| SimpleCov.enable_coverage(criterion) }
  end

  def spy_on_file_write
    write_calls = []
    original_write = File.method(:write)
    redefine_without_warning(File, :write) do |path, data, **opts|
      write_calls << opts if path.end_with?("index.html")
      original_write.call(path, data, **opts)
    end
    yield
    write_calls
  ensure
    redefine_without_warning(File, :write) { |*args, **opts| original_write.call(*args, **opts) }
  end

  def spy_on_cp_r
    cp_r_calls = []
    original_cp_r = FileUtils.method(:cp_r)
    redefine_without_warning(FileUtils, :cp_r) do |src, dst, **opts|
      cp_r_calls << opts
      original_cp_r.call(src, dst, **opts)
    end
    yield
    cp_r_calls
  ensure
    redefine_without_warning(FileUtils, :cp_r) { |*args, **opts| original_cp_r.call(*args, **opts) }
  end

  def redefine_without_warning(obj, method_name, &block)
    verbose = $VERBOSE
    $VERBOSE = nil
    obj.define_singleton_method(method_name, &block)
  ensure
    $VERBOSE = verbose
  end
end
