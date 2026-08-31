# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "unicode compatibility", :sandbox do
  before do
    setup_project("faked_project")
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start 'test_frameworks'
    RUBY
  end

  def expected_file_percents
    {
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00,
      "lib/faked_project/unicode.rb" => 66.66
    }
  end

  def expect_report_with_unicode_file(result)
    expect_coverage_report_generated(result)
    expect(result.output).to include("Coverage report generated for Unit Tests")

    data = html_report_data
    expect(reported_total_percent(data)).to eq(86.66)
    expect(reported_file_percents(data)).to eq(expected_file_percents)
    data.dig("coverage", "lib/faked_project/unicode.rb", "source")
  end

  it "handles a snowman inside a method string" do
    write_file("lib/faked_project/unicode.rb", <<~RUBY)
      # encoding: UTF-8
      class SourceCodeWithUnicode
        def self.yell!
          puts "☃"
        end
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    source = expect_report_with_unicode_file(result)
    expect(source.join("\n")).to include('puts "☃"')
  end

  it "handles an author name in a comment" do
    write_file("lib/faked_project/unicode.rb", <<~RUBY)
      # encoding: UTF-8
      # author:  Javiér Hernández
      class SomeClassWrittenByAForeigner
        def self.yell!
          foo
        end
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    source = expect_report_with_unicode_file(result)
    expect(source.join("\n")).to include("Javiér Hernández")
  end
end
