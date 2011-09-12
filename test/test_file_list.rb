require 'helper'

class TestFileList < Test::Unit::TestCase
  on_ruby "1.9" do
    context "With a file list from a result" do
      setup do
        original_result = {source_fixture('sample.rb') => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
            source_fixture('app/models/user.rb') => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
            source_fixture('app/controllers/sample_controller.rb') => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]}
        @file_list = SimpleCov::Result.new(original_result).files
      end

      should("have 13 covered_lines") { assert_equal 13, @file_list.covered_lines }
      should("have 2 missed_lines")   { assert_equal 2, @file_list.missed_lines }
      should("have 18 never_lines")   { assert_equal 18, @file_list.never_lines }
      should("have 15 lines_of_code") { assert_equal 15, @file_list.lines_of_code }
      should("have 3 skipped_lines")  { assert_equal 3, @file_list.skipped_lines }

      should "have correct covered_percent" do
        assert_equal 100.0*13/15, @file_list.covered_percent
      end
    end
  end
end
