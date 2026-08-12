# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# There are several equivalent ways to configure SimpleCov: inside the
# start block (plain, parameterized, or closing over outer variables),
# explicitly on SimpleCov before or after start, or via configure blocks.
# Each style must apply the same filter and command name.
RSpec.describe "configuration styles", :sandbox do
  before do
    setup_project("faked_project")
    configure_simplecov(:test_unit, "require 'simplecov'")
  end

  # The cucumber scenarios read "4 files" and "using Config Test Runner"
  # off the rendered page; the file list and footer are built from these
  # data fields (rendering is covered by the bun suite).
  def expect_config_applied
    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    data = html_report_data
    expect(data.fetch("coverage").keys.length).to eq(4)
    expect(data.dig("meta", "command_name")).to eq("Config Test Runner")
  end

  it "applies config inside the start block" do
    write_file(".simplecov", <<~RUBY)
      SimpleCov.start do
        add_filter 'test'
        command_name 'Config Test Runner'
      end
    RUBY
    expect_config_applied
  end

  it "applies config in a parameterized start block using an instance variable" do
    write_file(".simplecov", <<~RUBY)
      @filter = 'test'
      SimpleCov.start do |config|
        config.add_filter @filter
        config.command_name 'Config Test Runner'
      end
    RUBY
    expect_config_applied
  end

  it "applies config in a start block closing over a local variable" do
    write_file(".simplecov", <<~RUBY)
      filter = 'test'
      SimpleCov.start do
        add_filter filter
        command_name 'Config Test Runner'
      end
    RUBY
    expect_config_applied
  end

  it "applies config set explicitly before the start call" do
    write_file(".simplecov", <<~RUBY)
      SimpleCov.skip 'test'
      SimpleCov.command_name 'Config Test Runner'
      SimpleCov.start
    RUBY
    expect_config_applied
  end

  it "applies config set explicitly after the start call" do
    write_file(".simplecov", <<~RUBY)
      SimpleCov.start
      SimpleCov.skip 'test'
      SimpleCov.command_name 'Config Test Runner'
    RUBY
    expect_config_applied
  end

  it "applies a configure block after start" do
    write_file(".simplecov", <<~RUBY)
      SimpleCov.start
      SimpleCov.configure do
        add_filter 'test'
        command_name 'Config Test Runner'
      end
    RUBY
    expect_config_applied
  end

  it "applies a configure block before start" do
    write_file(".simplecov", <<~RUBY)
      SimpleCov.configure do
        add_filter 'test'
        command_name 'Config Test Runner'
      end
      SimpleCov.start
    RUBY
    expect_config_applied
  end

  it "applies mixed configure and start block config" do
    write_file(".simplecov", <<~RUBY)
      SimpleCov.configure do
        command_name 'Config Test Runner'
      end
      SimpleCov.start do
        add_filter 'test'
      end
    RUBY
    expect_config_applied
  end
end
