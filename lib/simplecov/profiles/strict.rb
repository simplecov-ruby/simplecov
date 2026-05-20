# frozen_string_literal: true

# A "no shortfalls allowed" profile: every supported coverage criterion
# is enabled and held to 100%. Per
# https://github.com/simplecov-ruby/simplecov/issues/1061, this lives as
# an opt-in profile rather than the default — most projects can't
# realistically start at 100% on day one — so a team that has paid down
# the debt can flip the strict switch without re-typing the threshold
# trio every time.
#
# Branch and method coverage need the corresponding Coverage features
# from the Ruby runtime, which JRuby doesn't provide. On JRuby the
# profile drops to enforcing line coverage only rather than tripping a
# disabled-criterion error.
SimpleCov.profiles.define "strict" do
  thresholds = {line: 100}
  if SimpleCov.branch_coverage_supported?
    enable_coverage :branch
    thresholds[:branch] = 100
  end
  if SimpleCov.method_coverage_supported?
    enable_coverage :method
    thresholds[:method] = 100
  end
  minimum_coverage thresholds
end
