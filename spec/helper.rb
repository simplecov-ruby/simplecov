# frozen_string_literal: true

require "rspec"
require "stringio"
require "open3"
require "tmpdir"
# loaded before simplecov to also capture parse time warnings
require "support/fail_rspec_on_ruby_warning"
require "simplecov"

SimpleCov.coverage_dir("tmp/coverage")

def source_fixture(filename)
  File.join(source_fixture_base_directory, "fixtures", filename)
end

def source_fixture_base_directory
  @source_fixture_base_directory ||= File.dirname(__FILE__)
end

def capture_stderr
  previous_stderr = $stderr
  $stderr = StringIO.new
  yield
  $stderr.string
ensure
  $stderr = previous_stderr
end

def capture_stdout
  previous_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = previous_stdout
end
