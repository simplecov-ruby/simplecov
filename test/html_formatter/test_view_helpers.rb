# frozen_string_literal: true

require "English"
require "helper"
require "coverage_fixtures"
require "set"

class TestViewHelpers < Minitest::Test
  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#coverage_css_class" if respond_to?(:cover)

  def test_coverage_css_class_green
    assert_equal "green", formatter.send(:coverage_css_class, 100)
    assert_equal "green", formatter.send(:coverage_css_class, 91)
    assert_equal "green", formatter.send(:coverage_css_class, 90)
  end

  def test_coverage_css_class_yellow
    assert_equal "yellow", formatter.send(:coverage_css_class, 89.99)
    assert_equal "yellow", formatter.send(:coverage_css_class, 76)
    assert_equal "yellow", formatter.send(:coverage_css_class, 75)
  end

  def test_coverage_css_class_red
    assert_equal "red", formatter.send(:coverage_css_class, 74.99)
    assert_equal "red", formatter.send(:coverage_css_class, 50)
    assert_equal "red", formatter.send(:coverage_css_class, 0)
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#id" if respond_to?(:cover)

  def test_id_returns_md5_hexdigest_of_filename
    source_file = stub_source_file("/path/to/file.rb")
    result = formatter.send(:id, source_file)

    assert_equal Digest::MD5.hexdigest("/path/to/file.rb"), result
  end

  def test_id_different_filenames_produce_different_ids
    file_a = stub_source_file("/a.rb")
    file_b = stub_source_file("/b.rb")

    refute_equal formatter.send(:id, file_a), formatter.send(:id, file_b)
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#timeago" if respond_to?(:cover)

  def test_timeago_generates_abbr_tag_with_iso8601
    time = Time.new(2026, 1, 15, 10, 30, 0)
    result = formatter.send(:timeago, time)

    assert_includes result, "<abbr"
    assert_includes result, 'class="timeago"'
    assert_includes result, "title=\"#{time.iso8601}\""
    assert_includes result, ">#{time.iso8601}</abbr>"
  end

  def test_timeago_uses_iso8601_in_both_title_and_content
    time = Time.new(2025, 6, 1, 12, 0, 0)
    result = formatter.send(:timeago, time)
    iso = time.iso8601

    assert_equal "<abbr class=\"timeago\" title=\"#{iso}\">#{iso}</abbr>", result
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#shortened_filename" if respond_to?(:cover)

  def test_shortened_filename_removes_root
    source_file = stub_source_file("#{SimpleCov.root}/lib/foo.rb")

    assert_equal "lib/foo.rb", formatter.send(:shortened_filename, source_file)
  end

  def test_shortened_filename_strips_dot_slash_prefix
    source_file = stub_source_file("#{SimpleCov.root}/bar.rb")
    result = formatter.send(:shortened_filename, source_file)

    refute result.start_with?("./"), "Expected no leading ./ but got: #{result}"
    assert_equal "bar.rb", result
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#link_to_source_file" if respond_to?(:cover)

  def test_link_to_source_file_generates_anchor
    source_file = stub_source_file("#{SimpleCov.root}/lib/foo.rb")
    result = formatter.send(:link_to_source_file, source_file)

    assert_includes result, "src_link"
    assert_includes result, "href=\"##{Digest::MD5.hexdigest(source_file.filename)}\""
    assert_includes result, "title=\"lib/foo.rb\""
    assert_includes result, ">lib/foo.rb</a>"
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#to_id" if respond_to?(:cover)

  def test_to_id_strips_leading_non_alpha
    assert_equal "abc", formatter.send(:to_id, "123abc")
    assert_equal "abc", formatter.send(:to_id, "---abc")
    assert_equal "a", formatter.send(:to_id, "a")
  end

  def test_to_id_strips_invalid_chars
    assert_equal "ab-c_d", formatter.send(:to_id, "ab-c_d!@#")
    assert_equal "abc", formatter.send(:to_id, "a.b.c")
  end

  def test_to_id_preserves_valid_ids
    assert_equal "AllFiles", formatter.send(:to_id, "AllFiles")
    assert_equal "my-group_1", formatter.send(:to_id, "my-group_1")
  end

  def test_to_id_returns_empty_for_all_invalid
    assert_equal "", formatter.send(:to_id, "123")
    assert_equal "", formatter.send(:to_id, "!@#")
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#fmt" if respond_to?(:cover)

  def test_fmt_small_numbers
    assert_equal "0", formatter.send(:fmt, 0)
    assert_equal "1", formatter.send(:fmt, 1)
    assert_equal "999", formatter.send(:fmt, 999)
  end

  def test_fmt_thousands
    assert_equal "1,000", formatter.send(:fmt, 1000)
    assert_equal "1,234", formatter.send(:fmt, 1234)
    assert_equal "9,999", formatter.send(:fmt, 9999)
  end

  def test_fmt_millions
    assert_equal "1,000,000", formatter.send(:fmt, 1_000_000)
    assert_equal "1,234,567", formatter.send(:fmt, 1_234_567)
  end

  def test_fmt_preserves_string_input
    assert_equal "12,345", formatter.send(:fmt, "12345")
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#build_stats" if respond_to?(:cover)

  def test_build_stats_basic
    stats = formatter.send(:build_stats, 80, 100)

    assert_equal 80, stats[:covered]
    assert_equal 100, stats[:total]
    assert_equal 20, stats[:missed]
    assert_in_delta 80.0, stats[:pct], 0.01
  end

  def test_build_stats_zero_total
    stats = formatter.send(:build_stats, 0, 0)

    assert_equal 0, stats[:covered]
    assert_equal 0, stats[:total]
    assert_equal 0, stats[:missed]
    assert_in_delta 100.0, stats[:pct], 0.01
  end

  def test_build_stats_full_coverage
    stats = formatter.send(:build_stats, 50, 50)

    assert_equal 0, stats[:missed]
    assert_in_delta 100.0, stats[:pct], 0.01
  end

  def test_build_stats_no_coverage
    stats = formatter.send(:build_stats, 0, 100)

    assert_equal 100, stats[:missed]
    assert_in_delta 0.0, stats[:pct], 0.01
  end

  def test_build_stats_returns_hash_with_four_keys
    stats = formatter.send(:build_stats, 3, 7)

    assert_equal %i[covered missed pct total], stats.keys.sort
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#line_status?" if respond_to?(:cover)

  def test_line_status_missed_branch
    set_coverage_flags(branch: true, method: false)

    source_file = stub_line_source(missed_branch_lines: [5])
    line = stub_line(5)

    assert_equal "missed-branch", formatter.send(:line_status?, source_file, line)
  end

  def test_line_status_no_missed_branch_returns_line_status
    set_coverage_flags(branch: true, method: false)

    source_file = stub_line_source(missed_branch_lines: [])
    line = stub_line(10, "covered")

    assert_equal "covered", formatter.send(:line_status?, source_file, line)
  end

  def test_line_status_without_branch_coverage_returns_line_status
    set_coverage_flags(branch: false, method: false)

    line = stub_line(1, "never")

    assert_equal "never", formatter.send(:line_status?, nil, line)
  end

  def test_line_status_missed_method
    set_coverage_flags(branch: false, method: true)

    source_file = stub_method_source("test.rb", missed_lines: [5, 6, 7])
    line = stub_line(6, "covered")

    assert_equal "missed-method", formatter.send(:line_status?, source_file, line)
  end

  def test_line_status_method_coverage_not_missed
    set_coverage_flags(branch: false, method: true)

    source_file = stub_method_source("test.rb", missed_lines: [5, 6, 7])
    line = stub_line(10, "covered")

    assert_equal "covered", formatter.send(:line_status?, source_file, line)
  end

  def test_line_status_branch_takes_priority_over_method
    set_coverage_flags(branch: true, method: true)

    source_file = stub_branch_priority_source
    line = stub_line(5)

    assert_equal "missed-branch", formatter.send(:line_status?, source_file, line)
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#coverage_summary" if respond_to?(:cover)

  def test_coverage_summary_renders_line_stats
    result = render_summary(covered_lines: 80, total_lines: 100)

    assert_includes result, "Line coverage:"
    assert_includes result, "80.00%"
  end

  def test_coverage_summary_renders_branch_stats
    f = new_formatter_with(branch: true)
    result = f.send(:coverage_summary, full_stats)

    assert_includes result, "Branch coverage:"
  end

  def test_coverage_summary_shows_branch_disabled_when_no_branch_coverage
    f = new_formatter_with(branch: false)
    result = f.send(:coverage_summary, zero_stats(covered_lines: 80, total_lines: 100))

    assert_includes result, "disabled"
  end

  def test_coverage_summary_defaults_branch_and_method_to_zero
    f = new_formatter_with(branch: true, method: true)
    result = f.send(:coverage_summary, {covered_lines: 80, total_lines: 100})

    assert_includes result, "Line coverage:"
    assert_includes result, "Branch coverage:"
    assert_includes result, "Method coverage:"
    assert_match(/Branch coverage:.*100.00%/m, result)
    assert_match(/Method coverage:.*100.00%/m, result)
  end

  def test_coverage_summary_with_show_method_toggle_true
    f = new_formatter_with(method: true)
    result = f.send(:coverage_summary, method_stats, show_method_toggle: true)

    assert_includes result, "t-missed-method-toggle"
  end

  def test_coverage_summary_with_show_method_toggle_false
    f = new_formatter_with(method: true)
    result = f.send(:coverage_summary, method_stats, show_method_toggle: false)

    refute_includes result, "t-missed-method-toggle"
  end

  def test_coverage_summary_default_show_method_toggle_is_false
    f = new_formatter_with(method: true)
    result = f.send(:coverage_summary, method_stats)

    refute_includes result, "t-missed-method-toggle"
    assert_includes result, "missed-method-text-color"
  end

  def test_coverage_summary_shows_missed_lines_when_present
    result = render_summary(covered_lines: 80, total_lines: 100)

    assert_includes result, "20"
    assert_includes result, "missed"
  end

  def test_coverage_summary_hides_missed_when_zero
    result = render_summary(covered_lines: 100, total_lines: 100)

    refute_match(%r{<span class="red"><b>0</b> missed</span>}, result)
  end

  def test_coverage_summary_shows_method_disabled_when_no_method_coverage
    f = new_formatter_with(method: false)
    result = f.send(:coverage_summary, zero_stats(covered_lines: 80, total_lines: 100))

    assert_match(/Method coverage:.*disabled/m, result)
  end

  def test_coverage_summary_with_all_coverages_enabled
    f = new_formatter_with(branch: true, method: true)
    result = f.send(:coverage_summary, full_stats)

    assert_includes result, "Line coverage:"
    assert_includes result, "Branch coverage:"
    assert_includes result, "Method coverage:"
  end

  def test_coverage_summary_passes_stats_to_template
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:coverage_summary, zero_stats(covered_lines: 42, total_lines: 50))

    assert_includes result, "42"
    assert_includes result, "50"
  end

  def test_coverage_summary_uses_build_stats_for_line
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:coverage_summary, {covered_lines: 75, total_lines: 100})

    assert_includes result, "75.00%"
    assert_includes result, "75"
    assert_includes result, "100"
  end

  def test_coverage_summary_uses_build_stats_for_branches
    f = new_formatter_with(branch: true)
    result = f.send(:coverage_summary, {
                      covered_lines: 80, total_lines: 100,
                      covered_branches: 6, total_branches: 8
                    })

    assert_includes result, "75.00%"
    assert_includes result, "6"
    assert_includes result, "8"
  end

  def test_coverage_summary_uses_build_stats_for_methods
    f = new_formatter_with(method: true)
    result = f.send(:coverage_summary, {
                      covered_lines: 80, total_lines: 100,
                      covered_methods: 3, total_methods: 4
                    })

    assert_includes result, "75.00%"
    assert_includes result, "3"
    assert_includes result, "4"
  end

  def test_coverage_summary_fetch_defaults_branch_covered_to_zero
    f = new_formatter_with(branch: true, method: false)
    result = f.send(:coverage_summary, {
                      covered_lines: 80, total_lines: 100,
                      total_branches: 10
                    })

    assert_includes result, "0/10 covered"
  end

  def test_coverage_summary_fetch_defaults_branch_total_to_zero
    f = new_formatter_with(branch: true, method: false)
    result = f.send(:coverage_summary, {
                      covered_lines: 80, total_lines: 100,
                      covered_branches: 0
                    })

    assert_includes result, "0/0 covered"
  end

  def test_coverage_summary_fetch_defaults_method_covered_to_zero
    f = new_formatter_with(branch: false, method: true)
    result = f.send(:coverage_summary, {
                      covered_lines: 80, total_lines: 100,
                      total_methods: 10
                    })

    assert_includes result, "0/10 covered"
  end

  def test_coverage_summary_fetch_defaults_method_total_to_zero
    f = new_formatter_with(branch: false, method: true)
    result = f.send(:coverage_summary, {
                      covered_lines: 80, total_lines: 100,
                      covered_methods: 0
                    })

    assert_includes result, "0/0 covered"
  end

  def test_coverage_summary_branch_missed_shown_when_nonzero
    f = new_formatter_with(branch: true)
    result = f.send(:coverage_summary, {
                      covered_lines: 80, total_lines: 100,
                      covered_branches: 5, total_branches: 10,
                      covered_methods: 0, total_methods: 0
                    })

    assert_includes result, "missed-branch-text"
    assert_includes result, "5"
  end

  def test_coverage_summary_method_missed_shown_when_nonzero_no_toggle
    f = new_formatter_with(method: true)
    result = f.send(:coverage_summary, {
                      covered_lines: 80, total_lines: 100,
                      covered_branches: 0, total_branches: 0,
                      covered_methods: 3, total_methods: 10
                    }, show_method_toggle: false)

    assert_includes result, "missed-method-text-color"
    assert_includes result, "7"
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#covered_percent" if respond_to?(:cover)

  def test_covered_percent_renders_template
    result = formatter.send(:covered_percent, 85.5)

    assert_includes result, "85.50%"
  end

  def test_covered_percent_renders_green_for_high
    result = formatter.send(:covered_percent, 95.0)

    assert_includes result, "green"
    assert_includes result, "95.00%"
  end

  def test_covered_percent_renders_yellow_for_medium
    result = formatter.send(:covered_percent, 80.0)

    assert_includes result, "yellow"
    assert_includes result, "80.00%"
  end

  def test_covered_percent_renders_red_for_low
    result = formatter.send(:covered_percent, 50.0)

    assert_includes result, "red"
    assert_includes result, "50.00%"
  end

  def test_covered_percent_zero
    result = formatter.send(:covered_percent, 0.0)

    assert_includes result, "0.00%"
    assert_includes result, "red"
  end

  def test_covered_percent_hundred
    result = formatter.send(:covered_percent, 100.0)

    assert_includes result, "100.00%"
    assert_includes result, "green"
  end

  def test_covered_percent_uses_floor_with_two_decimals
    result = formatter.send(:covered_percent, 85.999)

    assert_includes result, "85.99%"
  end

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#missed_method_line_set" if respond_to?(:cover)

  def test_missed_method_line_set_returns_set_of_line_numbers
    source_file = stub_method_source("test.rb", missed_lines: [5, 10])
    result = formatter.send(:missed_method_line_set, source_file)

    assert_instance_of Set, result
    assert_equal Set[5, 6, 7, 8, 9, 10], result
  end

  def test_missed_method_line_set_empty_when_no_missed_methods
    source_file = Object.new
    source_file.define_singleton_method(:missed_methods) { [] }
    result = formatter.send(:missed_method_line_set, source_file)

    assert_instance_of Set, result
    assert_empty result
  end

  def test_missed_method_line_set_multiple_methods
    result = formatter.send(:missed_method_line_set, two_method_source(5, 7, 20, 22))

    assert_equal Set[5, 6, 7, 20, 21, 22], result
  end

  def test_missed_method_line_set_skips_methods_with_nil_start_line
    result = formatter.send(:missed_method_line_set, two_method_source(nil, 7, 20, 22))

    assert_equal Set[20, 21, 22], result
  end

  def test_missed_method_line_set_skips_methods_with_nil_end_line
    result = formatter.send(:missed_method_line_set, two_method_source(5, nil, 20, 22))

    assert_equal Set[20, 21, 22], result
  end

  def test_missed_method_line_set_single_line_method
    source_file = single_method_source(5, 5)
    result = formatter.send(:missed_method_line_set, source_file)

    assert_equal Set[5], result
  end

  # -- file_data_attrs tests --------------------------------------------------

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#file_data_attrs" if respond_to?(:cover)

  def test_file_data_attrs_line_only
    set_coverage_flags(branch: false, method: false)
    sf = stub_data_attrs_source(covered: 8, missed: 2)
    result = formatter.send(:file_data_attrs, sf)

    assert_equal 'data-covered-lines="8" data-relevant-lines="10"', result
  end

  def test_file_data_attrs_with_branch_coverage
    set_coverage_flags(branch: true, method: false)
    sf = stub_data_attrs_source(covered: 5, missed: 3, covered_branches: 4, total_branches: 6)
    result = formatter.send(:file_data_attrs, sf)

    assert_equal 'data-covered-lines="5" data-relevant-lines="8" data-covered-branches="4" data-total-branches="6"', result
  end

  def test_file_data_attrs_with_method_coverage
    set_coverage_flags(branch: false, method: true)
    sf = stub_data_attrs_source(covered: 10, missed: 0, covered_methods: 3, total_methods: 5)
    result = formatter.send(:file_data_attrs, sf)

    assert_equal 'data-covered-lines="10" data-relevant-lines="10" data-covered-methods="3" data-total-methods="5"', result
  end

  def test_file_data_attrs_with_all_coverage
    set_coverage_flags(branch: true, method: true)
    sf = stub_data_attrs_source(covered: 7, missed: 3, covered_branches: 2, total_branches: 4, covered_methods: 1, total_methods: 2)
    result = formatter.send(:file_data_attrs, sf)

    expected = 'data-covered-lines="7" data-relevant-lines="10" ' \
               'data-covered-branches="2" data-total-branches="4" ' \
               'data-covered-methods="1" data-total-methods="2"'

    assert_equal expected, result
  end

  def test_file_data_attrs_relevant_lines_is_covered_plus_missed
    set_coverage_flags(branch: false, method: false)
    sf = stub_data_attrs_source(covered: 3, missed: 7)
    result = formatter.send(:file_data_attrs, sf)

    assert_includes result, 'data-relevant-lines="10"'
  end

  def test_file_data_attrs_separator_is_space
    set_coverage_flags(branch: false, method: false)
    sf = stub_data_attrs_source(covered: 1, missed: 1)
    result = formatter.send(:file_data_attrs, sf)

    assert_equal 'data-covered-lines="1" data-relevant-lines="2"', result
    assert_includes result, '" data-'
  end

  def test_file_data_attrs_key_names_contain_data_prefix
    set_coverage_flags(branch: true, method: true)
    sf = stub_data_attrs_source(covered: 1, missed: 0, covered_branches: 0, total_branches: 0, covered_methods: 0, total_methods: 0)
    result = formatter.send(:file_data_attrs, sf)

    result.scan(/data-[\w-]+/).each do |key|
      assert key.start_with?("data-"), "Expected data- prefix, got: #{key}"
    end
  end

  def test_file_data_attrs_zero_values
    set_coverage_flags(branch: false, method: false)
    sf = stub_data_attrs_source(covered: 0, missed: 0)
    result = formatter.send(:file_data_attrs, sf)

    assert_equal 'data-covered-lines="0" data-relevant-lines="0"', result
  end

  def test_file_data_attrs_no_branch_keys_without_branch_coverage
    set_coverage_flags(branch: false, method: false)
    sf = stub_data_attrs_source(covered: 5, missed: 5)
    result = formatter.send(:file_data_attrs, sf)

    refute_includes result, "covered-branches"
    refute_includes result, "total-branches"
  end

  def test_file_data_attrs_no_method_keys_without_method_coverage
    set_coverage_flags(branch: false, method: false)
    sf = stub_data_attrs_source(covered: 5, missed: 5)
    result = formatter.send(:file_data_attrs, sf)

    refute_includes result, "covered-methods"
    refute_includes result, "total-methods"
  end

  # -- coverage_bar tests -----------------------------------------------------

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#coverage_bar" if respond_to?(:cover)

  def test_coverage_bar_returns_html_div
    result = formatter.send(:coverage_bar, 85.0)

    assert_includes result, '<div class="coverage-bar">'
    assert_includes result, "</div></div>"
  end

  def test_coverage_bar_uses_green_for_high_percent
    result = formatter.send(:coverage_bar, 95.0)

    assert_includes result, "coverage-bar__fill--green"
  end

  def test_coverage_bar_uses_yellow_for_medium_percent
    result = formatter.send(:coverage_bar, 80.0)

    assert_includes result, "coverage-bar__fill--yellow"
  end

  def test_coverage_bar_uses_red_for_low_percent
    result = formatter.send(:coverage_bar, 50.0)

    assert_includes result, "coverage-bar__fill--red"
  end

  def test_coverage_bar_formats_width_with_one_decimal
    result = formatter.send(:coverage_bar, 85.67)

    assert_includes result, 'style="width: 85.6%"'
  end

  def test_coverage_bar_floors_width
    result = formatter.send(:coverage_bar, 99.99)

    assert_includes result, 'style="width: 99.9%"'
  end

  def test_coverage_bar_zero_percent
    result = formatter.send(:coverage_bar, 0.0)

    assert_includes result, 'style="width: 0.0%"'
    assert_includes result, "coverage-bar__fill--red"
  end

  def test_coverage_bar_hundred_percent
    result = formatter.send(:coverage_bar, 100.0)

    assert_includes result, 'style="width: 100.0%"'
    assert_includes result, "coverage-bar__fill--green"
  end

  def test_coverage_bar_exact_output_structure
    result = formatter.send(:coverage_bar, 90.0)

    expected = '<div class="bar-sizer"><div class="coverage-bar">' \
               '<div class="coverage-bar__fill coverage-bar__fill--green" style="width: 90.0%"></div>' \
               "</div></div>"

    assert_equal expected, result
  end

  # -- coverage_cells tests ---------------------------------------------------

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#coverage_cells" if respond_to?(:cover)

  def test_coverage_cells_returns_three_td_elements
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line)

    assert_equal 3, result.scan("<td").count
  end

  def test_coverage_cells_combined_cell_has_bar_and_pct
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line)

    assert_includes result, "coverage-bar"
    assert_includes result, "coverage-pct"
    assert_includes result, "coverage-cell"
  end

  def test_coverage_cells_pct_cell_contains_formatted_percent
    result = formatter.send(:coverage_cells, 85.999, 85, 100, type: :line)

    assert_includes result, "85.99%"
  end

  def test_coverage_cells_pct_floors_to_two_decimals
    result = formatter.send(:coverage_cells, 85.999, 85, 100, type: :line)

    assert_includes result, "85.99%"
    refute_includes result, "86.00%"
  end

  def test_coverage_cells_numerator_cell_has_covered_value
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line)

    assert_includes result, ">85/</td>"
  end

  def test_coverage_cells_denominator_cell_has_total_value
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line)

    assert_includes result, ">100</td>"
  end

  def test_coverage_cells_non_totals_has_data_order_attribute
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line)

    assert_includes result, 'data-order="85.00"'
  end

  def test_coverage_cells_totals_has_no_data_order
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line, totals: true)

    refute_includes result, "data-order"
  end

  def test_totals_cell_attrs_returns_four_elements_with_empty_order
    _, _, _, order = formatter.send(:totals_cell_attrs, :line, "green")

    assert_equal "", order
  end

  def test_coverage_cells_uses_green_css_class_for_high
    result = formatter.send(:coverage_cells, 95.0, 95, 100, type: :line)

    assert_includes result, "green"
  end

  def test_coverage_cells_uses_red_css_class_for_low
    result = formatter.send(:coverage_cells, 50.0, 50, 100, type: :line)

    assert_includes result, "red"
  end

  def test_coverage_cells_td_class_contains_css_color_non_totals
    result = formatter.send(:coverage_cells, 95.0, 95, 100, type: :line)
    cov_td = result.match(/<td class="cell--coverage cell--line-pct ([^"]+)"/)

    assert cov_td, "Expected to find coverage td with cell--line-pct class"
    assert_includes cov_td[1], "green"
  end

  def test_coverage_cells_td_class_contains_css_color_totals
    result = formatter.send(:coverage_cells, 95.0, 95, 100, type: :line, totals: true)
    cov_td = result.match(/<td class="cell--coverage strong t-totals__line-pct ([^"]+)"/)

    assert cov_td, "Expected to find coverage td with t-totals__line-pct class"
    assert_includes cov_td[1], "green"
  end

  def test_coverage_cells_td_class_red_for_low_non_totals
    result = formatter.send(:coverage_cells, 50.0, 50, 100, type: :line)
    cov_td = result.match(/<td class="cell--coverage cell--line-pct ([^"]+)"/)

    assert cov_td, "Expected to find coverage td"
    assert_includes cov_td[1], "red"
  end

  def test_coverage_cells_td_class_red_for_low_totals
    result = formatter.send(:coverage_cells, 50.0, 50, 100, type: :line, totals: true)
    cov_td = result.match(/<td class="cell--coverage strong t-totals__line-pct ([^"]+)"/)

    assert cov_td, "Expected to find coverage td"
    assert_includes cov_td[1], "red"
  end

  def test_coverage_cells_non_totals_uses_type_in_pct_class
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line)

    assert_includes result, "cell--line-pct"
  end

  def test_coverage_cells_non_totals_branch_type
    result = formatter.send(:coverage_cells, 75.0, 15, 20, type: :branch)

    assert_includes result, "cell--branch-pct"
  end

  def test_coverage_cells_totals_uses_type_in_pct_class
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line, totals: true)

    assert_includes result, "t-totals__line-pct"
  end

  def test_coverage_cells_totals_uses_type_in_num_class
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line, totals: true)

    assert_includes result, "t-totals__line-num"
  end

  def test_coverage_cells_totals_uses_type_in_den_class
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line, totals: true)

    assert_includes result, "t-totals__line-den"
  end

  def test_coverage_cells_totals_has_strong_classes
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line, totals: true)

    assert_includes result, "cell--coverage strong t-totals__line-pct"
    assert_includes result, "strong t-totals__line-num"
    assert_includes result, "strong t-totals__line-den"
  end

  def test_coverage_cells_non_totals_numerator_class
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line)

    assert_includes result, 'class="cell--numerator"'
  end

  def test_coverage_cells_non_totals_denominator_class
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line)

    assert_includes result, 'class="cell--denominator"'
  end

  def test_coverage_cells_formats_large_numbers_with_commas
    result = formatter.send(:coverage_cells, 85.0, 1234, 10_000, type: :line)

    assert_includes result, "1,234"
    assert_includes result, "10,000"
  end

  def test_coverage_cells_data_order_uses_two_decimals
    result = formatter.send(:coverage_cells, 75.555, 75, 100, type: :line)

    assert_includes result, 'data-order="75.56"'
  end

  def test_coverage_cells_exact_pct_format
    result = formatter.send(:coverage_cells, 100.0, 100, 100, type: :line)

    assert_includes result, "100.00%"
  end

  def test_coverage_cells_totals_pct_value_present
    result = formatter.send(:coverage_cells, 85.0, 85, 100, type: :line, totals: true)

    assert_includes result, "85.00%"
    assert_includes result, "coverage-pct"
  end

  # -- coverage_header_cells tests --------------------------------------------

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#coverage_header_cells" if respond_to?(:cover)

  def test_coverage_header_cells_contains_label
    result = formatter.send(:coverage_header_cells, "Line", :line, "Covered", "Total")

    assert_includes result, "Line"
  end

  def test_coverage_header_cells_contains_type_in_filter
    result = formatter.send(:coverage_header_cells, "Line", :line, "Covered", "Total")

    assert_includes result, 'data-type="line"'
  end

  def test_coverage_header_cells_contains_covered_label
    result = formatter.send(:coverage_header_cells, "Line", :line, "Covered Lines", "Total")

    assert_includes result, "Covered Lines"
  end

  def test_coverage_header_cells_contains_total_label
    result = formatter.send(:coverage_header_cells, "Line", :line, "Covered", "Total Lines")

    assert_includes result, "Total Lines"
  end

  def test_coverage_header_cells_contains_select_filter
    result = formatter.send(:coverage_header_cells, "Line", :line, "Covered", "Total")

    assert_includes result, "<select"
    assert_includes result, "col-filter__op"
  end

  def test_coverage_header_cells_contains_input_filter
    result = formatter.send(:coverage_header_cells, "Line", :line, "Covered", "Total")

    assert_includes result, '<input type="number"'
    assert_includes result, "col-filter__value"
  end

  def test_coverage_header_cells_has_no_colspan
    result = formatter.send(:coverage_header_cells, "Line", :line, "Covered", "Total")

    refute_includes result, "colspan"
    assert_includes result, "cell--coverage"
  end

  def test_coverage_header_cells_type_appears_in_both_filter_elements
    result = formatter.send(:coverage_header_cells, "Branch", :branch, "Covered", "Total")

    assert_equal 2, result.scan('data-type="branch"').count
  end

  def test_coverage_header_cells_th_label_span
    result = formatter.send(:coverage_header_cells, "My Label", :line, "Covered", "Total")

    assert_includes result, '<span class="th-label">My Label</span>'
  end

  # -- coverage_type_summary direct tests -------------------------------------

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#coverage_type_summary" if respond_to?(:cover)

  def test_coverage_type_summary_enabled_returns_div_with_type_class
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 80.0, covered: 80, total: 100, missed: 20}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, 'class="t-line-summary"'
  end

  def test_coverage_type_summary_disabled_delegates_to_disabled_summary
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:coverage_type_summary, "branch", "Branch coverage", {}, enabled: false)

    assert_includes result, "disabled"
    assert_includes result, "t-branch-summary"
  end

  def test_coverage_type_summary_contains_formatted_percent
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 85.999, covered: 85, total: 100, missed: 15}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, "85.99%"
  end

  def test_coverage_type_summary_percent_is_floored
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 85.999, covered: 85, total: 100, missed: 15}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, "85.99%"
    refute_includes result, "86.00%"
  end

  def test_coverage_type_summary_contains_css_class_from_pct
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 95.0, covered: 95, total: 100, missed: 5}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, '"green"'
  end

  def test_coverage_type_summary_css_class_red_for_low
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 50.0, covered: 50, total: 100, missed: 50}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, '"red"'
  end

  def test_coverage_type_summary_contains_covered_and_total
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 80.0, covered: 80, total: 100, missed: 20}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, "80/100"
  end

  def test_coverage_type_summary_default_suffix_is_covered
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 80.0, covered: 80, total: 100, missed: 20}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, "covered"
  end

  def test_coverage_type_summary_custom_suffix
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 80.0, covered: 80, total: 100, missed: 20}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true, suffix: "relevant lines covered")

    assert_includes result, "relevant lines covered"
  end

  def test_coverage_type_summary_suffix_key_is_used
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 100.0, covered: 10, total: 10, missed: 0}}
    result_default = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)
    result_custom = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true, suffix: "unique_suffix_text")

    assert_includes result_default, "10/10 covered"
    assert_includes result_custom, "10/10 unique_suffix_text"
    refute_includes result_custom, "10/10 covered"
  end

  def test_coverage_type_summary_ends_with_closing_div
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 100.0, covered: 100, total: 100, missed: 0}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert result.end_with?("</div>"), "Expected closing </div>, got: ...#{result[-30..]}"
  end

  def test_coverage_type_summary_contains_label
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 100.0, covered: 100, total: 100, missed: 0}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, "Line coverage:"
  end

  def test_coverage_type_summary_with_missed_includes_missed_count
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 80.0, covered: 80, total: 100, missed: 20}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, "<b>20</b> missed"
  end

  def test_coverage_type_summary_no_missed_when_zero
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 100.0, covered: 100, total: 100, missed: 0}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    refute_includes result, "missed"
  end

  def test_coverage_type_summary_missed_uses_default_red_class
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 80.0, covered: 80, total: 100, missed: 20}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, 'class="red"'
  end

  def test_coverage_type_summary_missed_uses_custom_missed_class
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 80.0, covered: 80, total: 100, missed: 20}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true, missed_class: "missed-branch-text")

    assert_includes result, 'class="missed-branch-text"'
    refute_includes result, 'class="red"'
  end

  def test_coverage_type_summary_toggle_false_uses_span
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 80.0, covered: 80, total: 100, missed: 20}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true, toggle: false)

    assert_includes result, "<span"
    refute_includes result, "t-missed-method-toggle"
  end

  def test_coverage_type_summary_toggle_true_uses_anchor
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 80.0, covered: 80, total: 100, missed: 20}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true, toggle: true)

    assert_includes result, "t-missed-method-toggle"
    assert_includes result, "<a href"
  end

  def test_coverage_type_summary_type_in_disabled_output
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:coverage_type_summary, "method", "Method coverage", {}, enabled: false)

    assert_includes result, "t-method-summary"
  end

  def test_coverage_type_summary_missed_includes_comma_separator
    f = new_formatter_with(branch: false, method: false)
    summary = {line: {pct: 80.0, covered: 80, total: 100, missed: 20}}
    result = f.send(:coverage_type_summary, "line", "Line coverage", summary, enabled: true)

    assert_includes result, %(<span class="coverage-cell__fraction">,</span>)
  end

  def test_coverage_type_summary_type_appears_in_enabled_div_class
    f = new_formatter_with(branch: false, method: false)
    summary = {branch: {pct: 75.0, covered: 15, total: 20, missed: 5}}
    result = f.send(:coverage_type_summary, "branch", "Branch coverage", summary, enabled: true)

    assert_includes result, "t-branch-summary"
  end

  # -- disabled_summary tests -------------------------------------------------

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#disabled_summary" if respond_to?(:cover)

  def test_disabled_summary_contains_type_in_class
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:disabled_summary, "branch", "Branch coverage")

    assert_includes result, "t-branch-summary"
  end

  def test_disabled_summary_contains_label
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:disabled_summary, "method", "Method coverage")

    assert_includes result, "Method coverage:"
  end

  def test_disabled_summary_contains_disabled_text
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:disabled_summary, "branch", "Branch coverage")

    assert_includes result, "disabled"
  end

  def test_disabled_summary_different_types_produce_different_classes
    f = new_formatter_with(branch: false, method: false)
    branch_result = f.send(:disabled_summary, "branch", "Branch coverage")
    method_result = f.send(:disabled_summary, "method", "Method coverage")

    assert_includes branch_result, "t-branch-summary"
    assert_includes method_result, "t-method-summary"
    refute_includes branch_result, "t-method-summary"
    refute_includes method_result, "t-branch-summary"
  end

  # -- missed_summary_html tests ----------------------------------------------

  cover "SimpleCov::Formatter::HTMLFormatter::ViewHelpers#missed_summary_html" if respond_to?(:cover)

  def test_missed_summary_html_no_toggle_uses_span_with_class
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:missed_summary_html, 5, "red", false)

    assert_includes result, '<span class="red"><b>5</b> missed</span>'
  end

  def test_missed_summary_html_with_toggle_uses_anchor
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:missed_summary_html, 7, "red", true)

    assert_includes result, '<a href="#" class="t-missed-method-toggle"><b>7</b> missed</a>'
  end

  def test_missed_summary_html_toggle_count_appears_in_output
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:missed_summary_html, 42, "red", true)

    assert_includes result, "<b>42</b>"
  end

  def test_missed_summary_html_starts_with_comma_separator
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:missed_summary_html, 5, "red", false)

    assert result.start_with?('<span class="coverage-cell__fraction">,</span>'), "Expected comma separator at start, got: #{result[0..60]}"
  end

  def test_missed_summary_html_no_toggle_uses_custom_class
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:missed_summary_html, 3, "missed-branch-text", false)

    assert_includes result, 'class="missed-branch-text"'
  end

  def test_missed_summary_html_returns_non_empty_string
    f = new_formatter_with(branch: false, method: false)
    result = f.send(:missed_summary_html, 1, "red", false)

    refute_empty result
    assert_includes result, "missed"
  end

private

  def formatter
    @formatter ||= SimpleCov::Formatter::HTMLFormatter.new
  end

  def stub_source_file(filename)
    obj = Object.new
    obj.define_singleton_method(:filename) { filename }
    obj
  end

  def stub_line(number, status = nil)
    obj = Object.new
    obj.define_singleton_method(:number) { number }
    obj.define_singleton_method(:status) { status } if status
    obj
  end

  def stub_line_source(missed_branch_lines:)
    obj = Object.new
    obj.define_singleton_method(:line_with_missed_branch?) { |n| missed_branch_lines.include?(n) }
    obj
  end

  def stub_method_source(filename, missed_lines:)
    missed_method = make_method_stub(missed_lines.first, missed_lines.last)
    obj = Object.new
    obj.define_singleton_method(:filename) { filename }
    obj.define_singleton_method(:missed_methods) { [missed_method] }
    obj
  end

  def stub_branch_priority_source
    obj = Object.new
    obj.define_singleton_method(:line_with_missed_branch?) { |_n| true }
    obj.define_singleton_method(:filename) { "priority.rb" }
    obj
  end

  def set_coverage_flags(branch: false, method: false)
    formatter.instance_variable_set(:@branch_coverage, branch)
    formatter.instance_variable_set(:@method_coverage, method)
  end

  def new_formatter_with(branch: nil, method: nil)
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.instance_variable_set(:@branch_coverage, branch) unless branch.nil?
    f.instance_variable_set(:@method_coverage, method) unless method.nil?
    f
  end

  def render_summary(covered_lines:, total_lines:)
    f = SimpleCov::Formatter::HTMLFormatter.new
    f.send(:coverage_summary, zero_stats(covered_lines: covered_lines, total_lines: total_lines))
  end

  def full_stats
    {
      covered_lines: 80, total_lines: 100,
      covered_branches: 10, total_branches: 20,
      covered_methods: 5, total_methods: 10
    }
  end

  def zero_stats(covered_lines: 0, total_lines: 0)
    {
      covered_lines: covered_lines, total_lines: total_lines,
      covered_branches: 0, total_branches: 0,
      covered_methods: 0, total_methods: 0
    }
  end

  def method_stats
    {
      covered_lines: 80, total_lines: 100,
      covered_branches: 0, total_branches: 0,
      covered_methods: 5, total_methods: 10
    }
  end

  def make_method_stub(start_line, end_line)
    m = Object.new
    m.define_singleton_method(:start_line) { start_line }
    m.define_singleton_method(:end_line) { end_line }
    m
  end

  def two_method_source(start1, end1, start2, end2)
    m1 = make_method_stub(start1, end1)
    m2 = make_method_stub(start2, end2)
    obj = Object.new
    obj.define_singleton_method(:missed_methods) { [m1, m2] }
    obj
  end

  def single_method_source(start_line, end_line)
    m1 = make_method_stub(start_line, end_line)
    obj = Object.new
    obj.define_singleton_method(:missed_methods) { [m1] }
    obj
  end

  def stub_data_attrs_source(covered:, missed:, **extras)
    define_countable_methods(
      Object.new,
      covered_lines: covered, missed_lines: missed,
      covered_branches: extras.fetch(:covered_branches, 0),
      total_branches: extras.fetch(:total_branches, 0),
      covered_methods: extras.fetch(:covered_methods, 0),
      methods: extras.fetch(:total_methods, 0)
    )
  end

  def define_countable_methods(obj, **attrs)
    attrs.each do |name, val|
      c = make_countable(val)
      obj.define_singleton_method(name) { c }
    end
    obj
  end

  def make_countable(value)
    obj = Object.new
    obj.define_singleton_method(:count) { value }
    obj
  end
end
