# frozen_string_literal: true

require "simplecov"
# require 'simplecov-cobertura'
require_relative "../lib/cli_acceptance"

# BUG: simplecov#853: Uncomment any 1 of the following '# BUG' lines (and the `require` above on line 4 if needed), to reproduce issue #853.
# Note that when a '# BUG' line is uncommented, the `using ...` list at the bottom of the HTML report index shows fewer reports being merged, and lower coverage numbers.
# SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter # merges properly
SimpleCov.formatter = SimpleCov::Formatter::SimpleFormatter # BUG: simplecov#853: merges incorrectly
# SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter # BUG: simplecov#853: merges incorrectly
# SimpleCov.formatters = Array(SimpleCov.formatter) # merges properly
# SimpleCov.formatters = Array(SimpleCov.formatters) # merges properly
# SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter] # merges properly
# SimpleCov.formatters = Array(SimpleCov.formatters) + [SimpleCov::Formatter::SimpleFormatter] # merges properly
# SimpleCov.formatters = Array(SimpleCov.formatters) + [SimpleCov::Formatter::CoberturaFormatter] # merges properly
# SimpleCov.formatters = [SimpleCov::Formatter::SimpleFormatter] # BUG: simplecov#853: merges incorrectly
# SimpleCov.formatters = [SimpleCov::Formatter::CoberturaFormatter] # BUG: simplecov#853: merges incorrectly
# SimpleCov.formatters = [SimpleCov::Formatter::CoberturaFormatter, SimpleCov::Formatter::HTMLFormatter] # merges properly

# SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(SimpleCov.formatters)
