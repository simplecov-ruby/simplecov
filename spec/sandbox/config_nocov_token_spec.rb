# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "custom nocov tokens", :sandbox do
  let(:nocov_token_config) do
    <<~RUBY
      require 'simplecov'
      SimpleCov.start 'test_frameworks' do
        nocov_token 'skippit'
      end
    RUBY
  end
  let(:skip_token_config) do
    <<~RUBY
      require 'simplecov'
      SimpleCov.start 'test_frameworks' do
        skip_token 'skippit'
      end
    RUBY
  end

  before { setup_project("faked_project") }

  def skipped_line_count(data = html_report_data)
    data.fetch("coverage").sum { |_file, file_data| Array(file_data["lines"]).count("ignored") }
  end

  def write_skippit_file
    write_file("lib/faked_project/nocov.rb", <<~RUBY)
      class SourceCodeWithNocov
        # :skippit:
        def some_weird_code
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
        # :skippit:
      end
    RUBY
  end

  def file_percents_with_skipped_nocov_file
    {
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00,
      "lib/faked_project/nocov.rb" => 100.00
    }
  end

  def expect_skippit_block_skipped(config)
    configure_simplecov(:test_unit, config)
    write_skippit_file

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for Unit Tests")

    data = html_report_data
    expect(reported_file_percents(data)).to eq(file_percents_with_skipped_nocov_file)
    expect(skipped_line_count(data)).to eq(7)
  end

  it "honors a custom token configured via nocov_token" do
    expect_skippit_block_skipped(nocov_token_config)
  end

  it "honors a custom token configured via skip_token" do
    expect_skippit_block_skipped(skip_token_config)
  end
end
