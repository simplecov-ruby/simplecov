# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# SimpleCov::Formatter::JSONFormatter is one of the formatters included
# by default, useful for exporting coverage results in JSON format.
RSpec.describe "JSON formatter", :sandbox do
  before { setup_project("faked_project") }

  it "generates a JSON coverage report" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
      SimpleCov.at_exit do
        puts SimpleCov.result.format!
      end
      SimpleCov.start do
        add_group 'Libs', 'lib/faked_project/'
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect(result.output).to include("JSON Coverage report generated")
    expect(result.output).to include("Coverage report generated")
    expect(file_exist?("coverage/coverage.json")).to be(true)
    expect(coverage_json.fetch("coverage").keys).to include("lib/faked_project/meta_magic.rb")
  end
end
