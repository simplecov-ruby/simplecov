# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Running specs with a failing rspec setup: an exception raised while
# loading the spec helper must fail the run.
RSpec.describe "rspec failing on initialization", :sandbox do
  before { setup_project("faked_project") }

  it "fails if rspec fails before starting its tests" do
    write_file("spec/spec_helper.rb", <<~RUBY)
      require 'simplecov'
      SimpleCov.start
      raise "some exception in the class loading before the tests start"
    RUBY

    result = run_command("bundle exec rspec spec")
    expect(result.exit_status).not_to eq(0)
  end
end
