# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "maximum coverage drop enforcement", :sandbox do
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

  let(:failing_spec) do
    <<~RUBY
      require "spec_helper"
      describe FakedProject do
        it "fails" do
          expect(false).to eq(true)
        end
      end
    RUBY
  end

  let(:branchy_failing_spec) do
    <<~RUBY
      require "spec_helper"
      describe FakedProject do
        it "fails" do
          false ? true : expect(false).to eq(true)
        end
      end
    RUBY
  end

  def last_run_json
    JSON.parse(read_file("coverage/.last_run.json"))
  end

  def write_last_run(result)
    write_file("coverage/.last_run.json", JSON.generate("result" => result))
  end

  def arrange_branch_drop(simplecov_config)
    configure_simplecov(:test_unit, simplecov_config)
    write_file("lib/faked_project/missed.rb", uncovered_source)
    write_file("spec/failing_spec.rb", branchy_failing_spec)
    write_last_run("line" => 100.0, "branch" => 100.0)
  end

  describe "a configured maximum" do
    before do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_filter 'test.rb'
          maximum_coverage_drop 3.14
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
    end

    context "when coverage has since dropped past it" do
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
          .to include("Line coverage has dropped by 3.31% since the last time (maximum allowed: 3.14%).")
      end

      it "keeps the last_run file" do
        expect(file_exist?("coverage/.last_run.json")).to be(true)
      end

      it "leaves the passing run's coverage recorded in it" do
        expect(last_run_json).to eq("result" => {"line" => 88.09})
      end
    end
  end

  describe "no configured maximum" do
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

      it "records the coverage in it" do
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

      it "updates the coverage in it" do
        expect(last_run_json).to eq("result" => {"line" => 84.78})
      end
    end
  end

  describe "a test failure alongside a drop" do
    let!(:result) do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_group 'Libs', 'lib/faked_project/'
          add_filter '/spec/'
          maximum_coverage_drop 0
        end
      RUBY
      write_file("lib/faked_project/missed.rb", uncovered_source)
      write_file("spec/failing_spec.rb", failing_spec)
      write_last_run("line" => 100.0)
      run_command(sorted_rspec_command)
    end

    it "fails on the tests" do
      expect(result.exit_status).to eq(1)
    end

    it "keeps the last_run file" do
      expect(file_exist?("coverage/.last_run.json")).to be(true)
    end

    it "leaves the recorded coverage alone" do
      expect(last_run_json).to eq("result" => {"line" => 100.0})
    end
  end

  describe "a legacy covered_percent last_run file" do
    let!(:result) do
      configure_simplecov(:test_unit, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_filter 'test.rb'
          maximum_coverage_drop 0
        end
      RUBY
      write_last_run("covered_percent" => 88.09)
      run_command("bundle exec rake test")
    end

    it "passes" do
      expect(result.exit_status).to eq(0)
    end

    it "keeps the last_run file" do
      expect(file_exist?("coverage/.last_run.json")).to be(true)
    end

    it "rewrites it in the current format" do
      expect(last_run_json).to eq("result" => {"line" => 88.09})
    end
  end

  describe "a legacy covered_percent last_run file when the tests fail" do
    let!(:result) do
      configure_simplecov(:rspec, <<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_group 'Libs', 'lib/faked_project/'
          add_filter '/spec/'
          maximum_coverage_drop 0
        end
      RUBY
      write_file("lib/faked_project/missed.rb", uncovered_source)
      write_file("spec/failing_spec.rb", failing_spec)
      write_last_run("covered_percent" => 100.0)
      run_command(sorted_rspec_command)
    end

    it "fails on the tests" do
      expect(result.exit_status).to eq(1)
    end

    it "keeps the last_run file" do
      expect(file_exist?("coverage/.last_run.json")).to be(true)
    end

    it "leaves it alone" do
      expect(last_run_json).to eq("result" => {"covered_percent" => 100.0})
    end
  end

  describe "line and branch thresholds together" do
    let!(:result) do
      arrange_branch_drop(<<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_filter 'test.rb'
          enable_coverage :branch
          maximum_coverage_drop line: 0, branch: 0
        end
      RUBY
      run_command("bundle exec rake test")
    end

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "announces the line drop" do
      expect(result.output)
        .to include("Line coverage has dropped by 15.22% since the last time (maximum allowed: 0.00%).")
    end

    it "announces the branch drop" do
      expect(result.output)
        .to include("Branch coverage has dropped by 50.00% since the last time (maximum allowed: 0.00%).")
    end

    it "exits 3" do
      expect(result.output).to include("SimpleCov failed with exit 3")
    end
  end

  describe "one threshold with branch as the primary criterion" do
    let!(:result) do
      arrange_branch_drop(<<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_filter 'test.rb'
          enable_coverage :branch
          primary_coverage :branch
          maximum_coverage_drop 0
        end
      RUBY
      run_command("bundle exec rake test")
    end

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "says nothing about lines" do
      expect(result.output).not_to include("Line coverage has dropped")
    end

    it "announces the branch drop" do
      expect(result.output)
        .to include("Branch coverage has dropped by 50.00% since the last time (maximum allowed: 0.00%).")
    end

    it "exits 3" do
      expect(result.output).to include("SimpleCov failed with exit 3")
    end
  end

  describe "both thresholds with branch as the primary criterion" do
    let!(:result) do
      arrange_branch_drop(<<~RUBY)
        require 'simplecov'
        SimpleCov.start do
          add_filter 'test.rb'
          enable_coverage :branch
          primary_coverage :branch
          maximum_coverage_drop line: 0, branch: 0
        end
      RUBY
      run_command("bundle exec rake test")
    end

    it "fails the run" do
      expect(result.exit_status).not_to eq(0)
    end

    it "announces the branch drop" do
      expect(result.output)
        .to include("Branch coverage has dropped by 50.00% since the last time (maximum allowed: 0.00%).")
    end

    it "announces the line drop" do
      expect(result.output)
        .to include("Line coverage has dropped by 15.22% since the last time (maximum allowed: 0.00%).")
    end

    it "exits 3" do
      expect(result.output).to include("SimpleCov failed with exit 3")
    end
  end
end
