# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

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

  describe "refuse_coverage_drop configured" do
    before do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_filter 'test.rb'
          refuse_coverage_drop
        end
      RUBY
    end

    context "when the suite first runs" do
      let!(:result) { run_command("bundle exec rake test") }

      it "passes" do
        expect(result.exit_status).to eq(0)
      end

      it "records the coverage" do
        expect(last_run_json).to eq("result" => {"line" => 88.09})
      end
    end

    context "when coverage has since dropped" do
      let!(:result) do
        run_command("bundle exec rake test")
        write_file("lib/faked_project/missed.rb", uncovered_source)
        run_command("bundle exec rake test")
      end

      it "fails the run" do
        expect(result.exit_status).not_to eq(0)
      end

      it "says how far coverage dropped" do
        expect(result.output)
          .to include("Line coverage has dropped by 3.31% since the last time (maximum allowed: 0.00%).")
      end

      it "leaves the recorded coverage alone" do
        expect(last_run_json).to eq("result" => {"line" => 88.09})
      end
    end
  end

  describe "refuse_coverage_drop not configured" do
    before do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_filter 'test.rb'
        end
      RUBY
    end

    context "when the suite first runs" do
      let!(:result) { run_command("bundle exec rake test") }

      it "passes" do
        expect(result.exit_status).to eq(0)
      end

      it "writes the last_run file" do
        expect(file_exist?("coverage/.last_run.json")).to be(true)
      end

      it "records the coverage" do
        expect(last_run_json).to eq("result" => {"line" => 88.09})
      end
    end

    context "when coverage has since dropped" do
      let!(:result) do
        run_command("bundle exec rake test")
        write_file("lib/faked_project/missed.rb", uncovered_source)
        run_command("bundle exec rake test")
      end

      it "passes" do
        expect(result.exit_status).to eq(0)
      end

      it "keeps the last_run file" do
        expect(file_exist?("coverage/.last_run.json")).to be(true)
      end

      it "updates the recorded coverage" do
        expect(last_run_json).to eq("result" => {"line" => 84.78})
      end
    end
  end
end
