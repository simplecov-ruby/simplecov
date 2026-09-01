# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "skipping code with simplecov directives", :sandbox do
  let(:block_disable_source) do
    <<~RUBY
      class SourceCodeWithDirective
        # simplecov:disable line
        def some_weird_code
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
        # simplecov:enable line
      end
    RUBY
  end
  let(:inline_disable_source) do
    <<~RUBY
      class SourceCodeWithDirective
        def boom(value)
          value || raise("absurd") # simplecov:disable
        end
      end
    RUBY
  end
  let(:block_disable_with_reason_source) do
    <<~RUBY
      class SourceCodeWithDirective
        # simplecov:disable line legacy adapter, scheduled for removal
        def some_weird_code
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
        # simplecov:enable line
      end
    RUBY
  end
  let(:directive_in_a_string_source) do
    <<~RUBY
      class SourceCodeWithDirective
        BANNER = "# simplecov:disable"
        def message
          BANNER
        end
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

  def run_with_directive_file(source)
    write_file("lib/faked_project/directive.rb", source)
    run_command_and_expect_success("bundle exec rake test")
  end

  def expect_unchanged_coverage_with_directive_file(result)
    expect_coverage_report_generated(result)
    expect(reported_file_percents(html_report_data)).to eq(
      "lib/faked_project.rb" => 100.00,
      "lib/faked_project/some_class.rb" => 80.00,
      "lib/faked_project/framework_specific.rb" => 75.00,
      "lib/faked_project/meta_magic.rb" => 100.00,
      "lib/faked_project/directive.rb" => 100.00
    )
  end

  describe "a block disabled for line coverage" do
    let!(:result) { run_with_directive_file(block_disable_source) }

    it "leaves the rest of the coverage unchanged" do
      expect_unchanged_coverage_with_directive_file(result)
    end

    it "skips the whole block" do
      expect(skipped_line_count).to eq(7)
    end
  end

  describe "an inline disable" do
    let!(:result) { run_with_directive_file(inline_disable_source) }

    it "leaves the rest of the coverage unchanged" do
      expect_unchanged_coverage_with_directive_file(result)
    end

    it "skips a single line" do
      expect(skipped_line_count).to eq(1)
    end
  end

  describe "a block disable with a free-form trailing reason" do
    let!(:result) { run_with_directive_file(block_disable_with_reason_source) }

    it "leaves the rest of the coverage unchanged" do
      expect_unchanged_coverage_with_directive_file(result)
    end

    it "skips the whole block" do
      expect(skipped_line_count).to eq(7)
    end
  end

  describe "a directive marker inside a string literal" do
    let!(:result) { run_with_directive_file(directive_in_a_string_source) }

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "skips nothing" do
      expect(skipped_line_count).to eq(0)
    end
  end
end
