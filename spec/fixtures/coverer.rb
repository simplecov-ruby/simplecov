# Script to gather coverage data to use in tests to go along with fixtures

require "coverage"
Coverage.start(:all)
require_relative "branch_tester_script"

p Coverage.result
