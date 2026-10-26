# frozen_string_literal: true

module SimpleCov
  # The files a runner loads to define its tests, by the naming conventions of
  # RSpec and Minitest. `test_helper.rb` matches Minitest's prefix but defines
  # no tests, so a selection of it alone would run nothing.
  TEST_FILE_NAME = /\A(?:test_(?!helper\.rb\z).*|.*_(?:test|spec))\.rb\z/

  # Where in its file a test id points: a line (`spec/a_spec.rb:12`), a line
  # and the Minitest test's name where tests share the line
  # (`test/a_test.rb:12[ATest#test_b]`), or RSpec's own id for an example
  # whose line it shares or a shared example (`spec/a_spec.rb[1:2:1]`). An id
  # without it is a whole file.
  TEST_ID_TAIL = /(?::\d+(?:\[.+\])?|\[\d+(?::\d+)*\])\z/
end
