# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "JSON formatter", :sandbox do
  before { setup_project("faked_project") }

  let!(:result) do
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
    run_command_and_expect_success("bundle exec rake test")
  end

  it "announces the JSON report" do
    expect(result.output).to include("JSON Coverage report generated")
  end

  it "announces the report" do
    expect(result.output).to include("Coverage report generated")
  end

  it "writes coverage.json" do
    expect(file_exist?("coverage/coverage.json")).to be(true)
  end

  it "covers the project's files" do
    expect(coverage_json.fetch("coverage").keys).to include("lib/faked_project/meta_magic.rb")
  end
end
