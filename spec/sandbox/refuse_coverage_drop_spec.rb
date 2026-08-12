# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# Exit code should be non-zero if the overall coverage decreases.
# And last_run file should not be overwritten with new coverage value.
RSpec.describe "refuse coverage drop enforcement", :sandbox do
  before { setup_project("faked_project") }

  let(:uncovered_source) do
    <<~RUBY
      class UncoveredSourceCode
        def foo
          never_reached
        rescue => err
          but no one cares about invalid ruby here
        end
      end
    RUBY
  end

  def last_run_json
    JSON.parse(read_file("coverage/.last_run.json"))
  end

  it "refuses any coverage drop when refuse_coverage_drop is configured" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
        refuse_coverage_drop
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
    expect(last_run_json).to eq("result" => {"line" => 88.09})

    write_file("lib/faked_project/missed.rb", uncovered_source)

    result = run_command("bundle exec rake test")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to include("Line coverage has dropped by 3.31% since the last time (maximum allowed: 0.00%).")
    # The last_run file must survive with the pre-drop value, not the 84.78%
    # this failing run measured (the read would raise if it were deleted).
    expect(last_run_json).to eq("result" => {"line" => 88.09})
  end

  it "updates the resultset when refuse_coverage_drop is not configured" do
    configure_simplecov(:test_unit, <<~RUBY)
      require 'simplecov'
      SimpleCov.start do
        skip 'test.rb'
      end
    RUBY

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
    expect(file_exist?("coverage/.last_run.json")).to be(true)
    expect(last_run_json).to eq("result" => {"line" => 88.09})

    write_file("lib/faked_project/missed.rb", uncovered_source)

    result = run_command("bundle exec rake test")
    expect(result.exit_status).to eq(0)
    expect(file_exist?("coverage/.last_run.json")).to be(true)
    expect(last_run_json).to eq("result" => {"line" => 84.78})
  end
end
