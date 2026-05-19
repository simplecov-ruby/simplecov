# frozen_string_literal: true

require "helper"

# Test to verify correct handling of deleted files
# See https://github.com/simplecov-ruby/simplecov/issues/9
describe "A source file which is subsequently deleted" do # rubocop:disable RSpec/DescribeClass
  it "does not cause an error" do
    Dir.chdir(File.join(File.dirname(__FILE__), "fixtures")) do
      # `Open3.capture3` (not backticks) so the subprocess's stderr —
      # which now carries the formatter's "Coverage report generated…"
      # status line (see issue #1060) — is absorbed instead of leaking
      # into this spec run's own output.
      _stdout, _stderr, status = Open3.capture3("ruby", "deleted_source_sample.rb")
      expect(status.exitstatus).to be_zero
    end
  end
end
