# frozen_string_literal: true

# A "no shortfalls allowed" profile: every coverage criterion is
# enabled and held to 100%. Per
# https://github.com/simplecov-ruby/simplecov/issues/1061, this lives as
# an opt-in profile rather than the default — most projects can't
# realistically start at 100% on day one — so a team that has paid down
# the debt can flip the strict switch without re-typing the threshold
# trio every time.
#
# JRuby gracefully degrades: `enable_coverage :branch` / `:method` are
# accepted (they just add to the configured criteria set), but the
# runtime can't actually measure them, so the corresponding stats never
# materialize. `CoverageViolations` skips threshold lookups for
# criteria not in the stats, so the `:branch` / `:method` clauses below
# silently no-op on JRuby and only `:line` is enforced.
SimpleCov.profiles.define "strict" do
  enable_coverage :branch
  enable_coverage :method
  minimum_coverage line: 100, branch: 100, method: 100
end
