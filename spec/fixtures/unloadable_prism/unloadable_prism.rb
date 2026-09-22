# frozen_string_literal: true

$LOAD_PATH.unshift(File.join(__dir__, "prism_stub"))
require_relative "../../../lib/simplecov"

SimpleCov.start do
  root __dir__
  command_name "unloadable prism"
  coverage_dir "tmp/coverage"
  formatter SimpleCov::Formatter::SimpleFormatter
  cover "lib/**/*.rb"
  if ARGV.include?("all")
    enable_coverage :branch, :method
    coverage(:branch) { ignore :eval_generated }
  end
end

require_relative "lib/loaded"
Loaded.sign(1)

SimpleCov.result.files.each do |file|
  puts "#{file.project_filename} #{file.covered_percent.floor}"
end
puts "prism attempted: #{defined?(Prism) ? "yes" : "no"}"
