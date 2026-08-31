# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "test/unit without simplecov", :sandbox do
  before { setup_project("faked_project") }

  it "generates no report without any config" do
    result = run_command_and_expect_success("bundle exec rake test")
    expect_no_coverage_report(result)
  end

  it "generates no report when configured but not started" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.configure do
        add_filter 'somefilter'
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect_no_coverage_report(result)
  end
end
