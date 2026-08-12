# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Code wrapped in :nocov: comment blocks does not count against the
# coverage numbers: the whole block is marked skipped ("ignored" in the
# report data) and the file still reports 100%. Rendering skipped lines
# with the "skipped" treatment is covered by the bun suite
# (html_frontend/test/render_source.test.ts).
#
# NOTE: `# :nocov:` is deprecated in favor of `# simplecov:disable` /
# `# simplecov:enable` (see skipping_with_directives_spec.rb).
RSpec.describe "skipping code blocks with :nocov:", :sandbox do
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

  def expect_unchanged_coverage_with_nocov_file(result)
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for Unit Tests")

    data = html_report_data
    expect(reported_file_percents(data)).to eq(unchanged_file_percents_with_nocov_file)
    expect(skipped_line_count(data)).to eq(7)
  end

  it "skips a nocov'd method without hurting the file's coverage" do
    write_file("lib/faked_project/nocov.rb", <<~RUBY)
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

    result = run_command_and_expect_success("bundle exec rake test")
    expect_unchanged_coverage_with_nocov_file(result)
  end

  it "recognizes nocov tokens regardless of surrounding whitespace" do
    write_file("lib/faked_project/nocov.rb", <<~RUBY)
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

    result = run_command_and_expect_success("bundle exec rake test")
    expect_unchanged_coverage_with_nocov_file(result)
  end
end
