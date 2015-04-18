require "helper"

class TestFileList < Minitest::Test
  context "With a file list from a result" do
    setup do
      original_result = {
        source_fixture("sample.rb") => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
        source_fixture("app/models/user.rb") => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
        source_fixture("app/controllers/sample_controller.rb") => [nil, 2, 2, 0, nil, nil, 0, nil, nil, nil],
      }
      @file_list = SimpleCov::Result.new(original_result).files
    end

    should("have 11 covered_lines") { assert_equal 11, @file_list.covered_lines }
    should("have 3 missed_lines")   { assert_equal 3, @file_list.missed_lines }
    should("have 19 never_lines")   { assert_equal 19, @file_list.never_lines }
    should("have 14 lines_of_code") { assert_equal 14, @file_list.lines_of_code }
    should("have 3 skipped_lines")  { assert_equal 3, @file_list.skipped_lines }

    should("have correct covered_percent") { assert_equal 100.0 * 11 / 14, @file_list.covered_percent }
    should("have correct covered_strength") { assert_equal 13.to_f / 14, @file_list.covered_strength }
  end
end if SimpleCov.usable?
