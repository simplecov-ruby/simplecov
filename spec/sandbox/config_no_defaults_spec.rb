# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "no_defaults configuration", :sandbox do
  before { setup_project("faked_project") }

  it "loads no default formatter, so a resultset is written but no report rendered" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov/no_defaults'

      SimpleCov.start do
        command_name "No Defaults"
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect(file_exist?("coverage/.resultset.json")).to be(true)
    expect(file_exist?("coverage/index.html")).to be(false)
    expect(result.output).not_to include("Coverage report generated")
  end

  it "loads no default filters, so the report keeps the test files" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov/no_defaults'
      require 'simplecov/formatter/html_formatter'

      SimpleCov.start do
        formatter SimpleCov::Formatter::HTMLFormatter
        command_name "No Defaults"
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)

    files = html_report_data.fetch("coverage").keys
    expect(files.length).to eq(6)
    expect(files).to include("test/some_class_test.rb", "test/meta_magic_test.rb")
  end
end
