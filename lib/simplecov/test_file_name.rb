# frozen_string_literal: true

module SimpleCov
  # The files a runner loads to define its tests, by the naming conventions of
  # RSpec and Minitest. `test_helper.rb` matches Minitest's prefix but defines
  # no tests, so a selection of it alone would run nothing.
  TEST_FILE_NAME = /\A(?:test_(?!helper\.rb\z).*|.*_(?:test|spec))\.rb\z/
end
