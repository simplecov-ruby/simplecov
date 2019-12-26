# Script to gather coverage data to use in tests to go along with fixtures

require "coverage"
Coverage.start(:all)
require_relative "branches"

Branches.new.call(42)

p Coverage.result
