# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# RSpec failing in different ways results in SimpleCov saying something
# beforehand. However it doesn't identify itself as the originator of
# said error, and it preserves the original exit status.
RSpec.describe "rspec failing runs", :sandbox do
  before { setup_project("faked_project") }

  it "notes the previous error without claiming the exit status for a failing spec" do
    result = run_command("bundle exec rspec bad_spec/failing_spec.rb")
    expect(result.exit_status).not_to eq(0)
    expect(result.output).to match(/SimpleCov.+previous.+error/)
    expect(result.output).not_to match(/SimpleCov.+exit.+with.+status/)
  end

  it "preserves an explicit exit status" do
    result = run_command("bundle exec rspec bad_spec/fail_with_5.rb")
    expect(result.exit_status).to eq(5)
    expect(result.output).to match(/SimpleCov.+previous.+error/)
    expect(result.output).not_to match(/SimpleCov.+exit.+with.+status/)
  end
end
