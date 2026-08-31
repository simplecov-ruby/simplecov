# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "configuration profiles", :sandbox do
  before do
    setup_project("faked_project")
    configure_simplecov(:test_unit, "require 'simplecov'")
  end

  def expect_profile_applied(command_name)
    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    data = html_report_data
    expect(data.fetch("coverage").keys.length).to eq(4)
    expect(data.dig("meta", "command_name")).to eq(command_name)
  end

  it "defines and loads a custom profile inside the start block" do
    write_file(".simplecov", <<~RUBY)
      SimpleCov.profiles.define 'custom_command' do
        command_name "Profile Command"
      end

      SimpleCov.start do
        load_profile 'test_frameworks'
        load_profile 'custom_command'
      end
    RUBY
    expect_profile_applied("Profile Command")
  end

  it "nests profiles and passes the profile name to start" do
    write_file(".simplecov", <<~RUBY)
      SimpleCov.profiles.define 'my_profile' do
        load_profile 'test_frameworks'
        command_name "My Profile"
      end

      SimpleCov.start 'my_profile'
    RUBY
    expect_profile_applied("My Profile")
  end
end
