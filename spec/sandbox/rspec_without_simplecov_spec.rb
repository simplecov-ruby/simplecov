# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Running specs without simplecov configuration generates no report —
# whether there is no config at all or simplecov is configured but
# never started.
RSpec.describe "rspec without simplecov", :sandbox do
  before { setup_project("faked_project") }

  it "generates no report without any config" do
    result = run_command_and_expect_success("bundle exec rspec spec")
    expect_no_coverage_report(result)
  end

  it "generates no report when configured but not started" do
    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.configure do
        skip 'somefilter'
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rspec spec")
    expect_no_coverage_report(result)
  end
end
