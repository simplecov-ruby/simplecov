# frozen_string_literal: true

# A "no shortfalls allowed" profile: every coverage criterion is
# enabled and held to 100%. Per
# https://github.com/simplecov-ruby/simplecov/issues/1061, this lives as
# an opt-in profile rather than the default — most projects can't
# realistically start at 100% on day one — so a team that has paid down
# the debt can flip the strict switch without re-typing the threshold
# trio every time.
#
# `:eval` widens the universe of code held to 100% to include strings
# passed through `Kernel#eval` (typically ERB templates, when the user
# sets `ERB#filename=`).
SimpleCov.profiles.define "strict" do
  enable_coverage :branch
  enable_coverage :method
  enable_coverage :eval
  minimum_coverage line: 100, branch: 100, method: 100
end
