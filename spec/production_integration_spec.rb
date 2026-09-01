# frozen_string_literal: true

require "helper"
require "simplecov/production"

RSpec.describe "production coverage integration" do
  oneshot_supported = !Coverage.respond_to?(:supported?) || Coverage.supported?(:oneshot_lines)

  if oneshot_supported
    around do |test|
      Dir.chdir(File.join(File.dirname(__FILE__), "fixtures", "production_test")) do
        FileUtils.rm_rf("./tmp")
        test.call
      end
    end

    def run_fixture(mode)
      _out, stderr, status = Open3.capture3("bundle e ruby production_test.rb #{mode}")
      raise "fixture failed: #{stderr}" unless status.success?
    end

    def stored_coverage
      SimpleCov::Production::FileSink.read("tmp/production.json").fetch("coverage")
    end

    def line_of(source_fragment)
      File.readlines("workload.rb").index { |line| line.include?(source_fragment) } + 1
    end

    context "when one process has run" do
      before { run_fixture("even") }

      it "records the lines it executed, root-relative" do
        expect(stored_coverage.fetch("workload.rb")).to include(line_of("2 + 2"))
      end

      it "records nothing it did not execute" do
        expect(stored_coverage.fetch("workload.rb")).not_to include(line_of("3 + 3"))
      end
    end

    context "when separate processes have run" do
      before do
        run_fixture("even")
        run_fixture("odd")
      end

      it "union-merges the first one's lines into the shared store" do
        expect(stored_coverage.fetch("workload.rb")).to include(line_of("2 + 2"))
      end

      it "union-merges the second one's lines into the shared store" do
        expect(stored_coverage.fetch("workload.rb")).to include(line_of("3 + 3"))
      end
    end
  end
end
