# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "rspec failing runs", :sandbox do
  before { setup_project("faked_project") }

  describe "a failing spec" do
    let!(:result) { run_command("bundle exec rspec bad_spec/failing_spec.rb") }

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "notes the previous error" do
      expect(result.output).to match(/SimpleCov.+previous.+error/)
    end

    it "does not claim the exit status" do
      expect(result.output).not_to match(/SimpleCov.+exit.+with.+status/)
    end
  end

  describe "a spec that exits with an explicit status" do
    let!(:result) { run_command("bundle exec rspec bad_spec/fail_with_5.rb") }

    it "preserves that status" do
      expect(result.exit_status).to eq(5)
    end

    it "notes the previous error" do
      expect(result.output).to match(/SimpleCov.+previous.+error/)
    end

    it "does not claim the exit status" do
      expect(result.output).not_to match(/SimpleCov.+exit.+with.+status/)
    end
  end
end
