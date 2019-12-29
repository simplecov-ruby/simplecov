# Script to gather coverage data to use in tests to go along with fixtures

require "coverage"
Coverage.start(:all)
require_relative "case_without_else"
Case.call(42)

p Coverage.result
