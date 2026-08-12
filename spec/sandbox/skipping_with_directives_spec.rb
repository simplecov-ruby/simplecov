# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Code wrapped in `# simplecov:disable` / `# simplecov:enable` comment
# blocks (or trailed by an inline `# simplecov:disable`) does not count
# against the coverage numbers. Rendering skipped lines is covered by
# the bun suite (html_frontend/test/render_source.test.ts).
RSpec.describe "skipping code with simplecov directives", :sandbox do
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

  it "skips a block disabled for line coverage" do
    write_file("lib/faked_project/directive.rb", <<~RUBY)
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

    result = run_command_and_expect_success("bundle exec rake test")
    expect_unchanged_coverage_with_directive_file(result)
    expect(skipped_line_count).to eq(7)
  end

  it "skips a single line with an inline disable" do
    write_file("lib/faked_project/directive.rb", <<~RUBY)
      class SourceCodeWithDirective
        def boom(value)
          value || raise("absurd") # simplecov:disable
        end
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect_unchanged_coverage_with_directive_file(result)
    expect(skipped_line_count).to eq(1)
  end

  it "allows a free-form trailing reason on a block disable" do
    write_file("lib/faked_project/directive.rb", <<~RUBY)
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

    result = run_command_and_expect_success("bundle exec rake test")
    expect_unchanged_coverage_with_directive_file(result)
    expect(skipped_line_count).to eq(7)
  end

  it "ignores directive markers inside string literals" do
    write_file("lib/faked_project/directive.rb", <<~RUBY)
      class SourceCodeWithDirective
        BANNER = "# simplecov:disable"
        def message
          BANNER
        end
      end
    RUBY

    result = run_command_and_expect_success("bundle exec rake test")
    expect_coverage_report_generated(result)
    expect(skipped_line_count).to eq(0)
  end
end
