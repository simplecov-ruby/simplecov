# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "configuration styles", :sandbox do
  let(:start_block) do
    <<~RUBY
      SimpleCov.start do
        add_filter 'test'
        command_name 'Config Test Runner'
      end
    RUBY
  end
  let(:parameterized_start_block) do
    <<~RUBY
      @filter = 'test'
      SimpleCov.start do |config|
        config.add_filter @filter
        config.command_name 'Config Test Runner'
      end
    RUBY
  end
  let(:start_block_over_a_local) do
    <<~RUBY
      filter = 'test'
      SimpleCov.start do
        add_filter filter
        command_name 'Config Test Runner'
      end
    RUBY
  end
  let(:explicit_before_start) do
    <<~RUBY
      SimpleCov.skip 'test'
      SimpleCov.command_name 'Config Test Runner'
      SimpleCov.start
    RUBY
  end
  let(:explicit_after_start) do
    <<~RUBY
      SimpleCov.start
      SimpleCov.skip 'test'
      SimpleCov.command_name 'Config Test Runner'
    RUBY
  end
  let(:configure_after_start) do
    <<~RUBY
      SimpleCov.start
      SimpleCov.configure do
        add_filter 'test'
        command_name 'Config Test Runner'
      end
    RUBY
  end
  let(:configure_before_start) do
    <<~RUBY
      SimpleCov.configure do
        add_filter 'test'
        command_name 'Config Test Runner'
      end
      SimpleCov.start
    RUBY
  end
  let(:configure_and_start_block) do
    <<~RUBY
      SimpleCov.configure do
        command_name 'Config Test Runner'
      end
      SimpleCov.start do
        add_filter 'test'
      end
    RUBY
  end

  before do
    setup_project("faked_project")
    configure_simplecov(:test_unit, "require 'simplecov'")
  end

  def expect_config_applied(dotfile)
    write_file(".simplecov", dotfile)
    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    data = html_report_data
    expect(data.fetch("coverage").keys.length).to eq(4)
    expect(data.dig("meta", "command_name")).to eq("Config Test Runner")
  end

  it "applies config inside the start block" do
    expect_config_applied(start_block)
  end

  it "applies config in a parameterized start block using an instance variable" do
    expect_config_applied(parameterized_start_block)
  end

  it "applies config in a start block closing over a local variable" do
    expect_config_applied(start_block_over_a_local)
  end

  it "applies config set explicitly before the start call" do
    expect_config_applied(explicit_before_start)
  end

  it "applies config set explicitly after the start call" do
    expect_config_applied(explicit_after_start)
  end

  it "applies a configure block after start" do
    expect_config_applied(configure_after_start)
  end

  it "applies a configure block before start" do
    expect_config_applied(configure_before_start)
  end

  it "applies mixed configure and start block config" do
    expect_config_applied(configure_and_start_block)
  end
end
