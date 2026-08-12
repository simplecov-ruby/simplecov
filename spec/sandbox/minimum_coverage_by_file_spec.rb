# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Exit code should be non-zero if the coverage of any one file is below
# the configured value.
RSpec.describe "minimum coverage by file enforcement", :sandbox do
  before { setup_project("faked_project") }

  it "fails slightly under minimum coverage by file" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        minimum_coverage_by_file 75.01
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include(
      "Line coverage by file (75.00%) is below the expected minimum coverage (75.01%) " \
      "in lib/faked_project/framework_specific.rb."
    )
    expect(result.output).to include("SimpleCov failed with exit 2")
  end

  it "just passes it" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        minimum_coverage_by_file 75
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
  end

  it "works together with branch coverage and the new criterion announcing both failures" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        enable_coverage :branch
        minimum_coverage_by_file line: 90, branch: 70
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include(
      "Line coverage by file (80.00%) is below the expected minimum coverage (90.00%) " \
      "in lib/faked_project/some_class.rb."
    )
    expect(result.output).to include(
      "Branch coverage by file (50.00%) is below the expected minimum coverage (70.00%) " \
      "in lib/faked_project/some_class.rb."
    )
    expect(result.output).to include("SimpleCov failed with exit 2")
  end

  it "can set branch as primary coverage and it will fail if branch is below minimum coverage" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        enable_coverage :branch
        primary_coverage :branch
        minimum_coverage_by_file 70
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include(
      "Branch coverage by file (50.00%) is below the expected minimum coverage (70.00%) " \
      "in lib/faked_project/some_class.rb."
    )
    expect(result.output).not_to include("Line coverage (")
    expect(result.output).to include("SimpleCov failed with exit 2")
  end

  it "raises the bar for a specific file with a per-path override" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        minimum_coverage_by_file line: 70, 'lib/faked_project/framework_specific.rb' => 100
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include(
      "Line coverage by file (75.00%) is below the expected minimum coverage (100.00%) " \
      "in lib/faked_project/framework_specific.rb."
    )
    expect(result.output).to include("SimpleCov failed with exit 2")
  end

  it "does not flag files that pass the default but not the override" do
    # framework_specific.rb is at 75% -- passes the default 70%; some_class.rb is
    # at 80% -- passes both. The directory-prefix override raises the bar to 90%
    # for lib/faked_project/, so framework_specific.rb fails its override.
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        minimum_coverage_by_file line: 70, 'lib/faked_project/' => 90
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include(
      "Line coverage by file (75.00%) is below the expected minimum coverage (90.00%) " \
      "in lib/faked_project/framework_specific.rb."
    )
    expect(result.output).to include("SimpleCov failed with exit 2")
  end

  it "has no effect from a per-path override that no file matches" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        add_filter 'test.rb'
        minimum_coverage_by_file line: 70, 'lib/nonexistent.rb' => 100
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
  end
end
