# frozen_string_literal: true

require "simplecov/production"

sink = SimpleCov::Production::FileSink.new(path: File.join(__dir__, "tmp", "production.json"))
SimpleCov::Production.start(root: __dir__, sink: sink, flush_interval: 600)

require_relative "workload"
Workload.run(ARGV.fetch(0, "even"))

SimpleCov::Production.stop
