# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "rspec failing on initialization", :sandbox do
  before do
    setup_project("faked_project")
    write_file("spec/spec_helper.rb", <<~RUBY)
      require 'simplecov'
      SimpleCov.start
      raise "some exception in the class loading before the tests start"
    RUBY
  end

  it "fails if rspec fails before starting its tests" do
    expect(run_command("bundle exec rspec spec").exit_status).not_to eq(0)
  end
end
