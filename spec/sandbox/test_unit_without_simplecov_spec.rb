# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "test/unit without simplecov", :sandbox do
  let(:configured_but_unstarted) do
    <<~RUBY
      require 'simplecov'
      SimpleCov.configure do
        add_filter 'somefilter'
      end
    RUBY
  end

  before { setup_project("faked_project") }

  it "generates no report without any config" do
    expect_no_coverage_report(run_command_and_expect_success("bundle exec rake test"))
  end

  it "generates no report when configured but not started" do
    configure_simplecov(:test_unit, configured_but_unstarted)

    expect_no_coverage_report(run_command_and_expect_success("bundle exec rake test"))
  end
end
