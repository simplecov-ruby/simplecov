# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "skipping code blocks with :nocov:", :sandbox do
  let(:tight_nocov_source) do
    <<~RUBY
      class SourceCodeWithNocov
        #:nocov:
        def some_weird_code
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
        #:nocov:
      end
    RUBY
  end
  let(:padded_nocov_source) do
    <<~RUBY
      class SourceCodeWithNocov
           #    :nocov:
        def some_weird_code
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
          #   :nocov:
      end
    RUBY
  end

  before do
    setup_project("faked_project")
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start 'test_frameworks'
    RUBY
  end

  def skipped_line_count(data = html_report_data)
    data.fetch("coverage").sum { |_file, file_data| Array(file_data["lines"]).count("ignored") }
  end

  def unchanged_file_percents_with_nocov_file
    {
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00,
      "lib/faked_project/nocov.rb" => 100.00
    }
  end

  def expect_unchanged_coverage_with_nocov_file(source)
    write_file("lib/faked_project/nocov.rb", source)
    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for Unit Tests")

    data = html_report_data
    expect(reported_file_percents(data)).to eq(unchanged_file_percents_with_nocov_file)
    expect(skipped_line_count(data)).to eq(7)
  end

  it "skips a nocov'd method without hurting the file's coverage" do
    expect_unchanged_coverage_with_nocov_file(tight_nocov_source)
  end

  it "recognizes nocov tokens regardless of surrounding whitespace" do
    expect_unchanged_coverage_with_nocov_file(padded_nocov_source)
  end
end
