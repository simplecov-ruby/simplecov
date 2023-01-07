require "simplecov"
SimpleCov.enable_coverage_for_eval
SimpleCov.start "rails"

file = File.join(__dir__, "eval_test.erb")
erb = ERB.new(File.read(file))
erb.filename = file
erb.run
