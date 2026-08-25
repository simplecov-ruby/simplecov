# frozen_string_literal: true

require "helper"
require "simplecov/production"

RSpec.describe "production coverage integration" do # rubocop:disable RSpec/DescribeClass
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

    it "records the lines one process executed, root-relative" do
      run_fixture("even")

      lines = stored_coverage.fetch("workload.rb")
      expect(lines).to include(line_of("2 + 2"))
      expect(lines).not_to include(line_of("3 + 3"))
    end

    it "union-merges runs from separate processes into the shared store" do
      run_fixture("even")
      run_fixture("odd")

      lines = stored_coverage.fetch("workload.rb")
      expect(lines).to include(line_of("2 + 2"))
      expect(lines).to include(line_of("3 + 3"))
    end
  end
end
