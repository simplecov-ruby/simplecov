# frozen_string_literal: true

require "rspec"
require "stringio"
require "open3"
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
