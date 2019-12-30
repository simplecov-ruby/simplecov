# Script to gather coverage data to use in tests to go along with fixtures

require "coverage"
Coverage.start(:all)
require_relative "nocov_complex"
NoCovComplex.call(41)

p Coverage.result
