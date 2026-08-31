# frozen_string_literal: true

require "helper"
require "support/sandbox_project"
require "tmpdir"

RSpec.describe "custom coverage directory", :sandbox do
  before { setup_project("faked_project") }

  it "writes the report to a relative custom directory" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        coverage_dir 'test/simplecov'
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result, coverage_dir: "test/simplecov")
    expect(file_exist?("coverage")).to be(false)
  end

  it "writes the report to an absolute custom directory" do
    absolute_dir = File.join(Dir.tmpdir, "simplecov-sandbox-#{Process.pid}", "test", "simplecov")
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        coverage_dir '#{absolute_dir}'
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect(result.output).to include("Coverage report generated")
    expect(File.exist?(File.join(absolute_dir, "index.html"))).to be(true)
    expect(File.exist?(File.join(absolute_dir, ".resultset.json"))).to be(true)
    expect(file_exist?("coverage")).to be(false)
  ensure
    FileUtils.rm_rf(File.join(Dir.tmpdir, "simplecov-sandbox-#{Process.pid}"))
  end
end
