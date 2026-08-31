# frozen_string_literal: true

# Every coverage criterion enabled and held to 100%. An opt-in profile rather
# than the default (#1061), so a team that has paid down the debt can flip the
# strict switch without re-typing the threshold trio every time.
#
# JRuby gracefully degrades: `enable_coverage :branch` / `:method` are accepted
# but the runtime cannot measure them, and `CoverageViolations` skips threshold
# lookups for criteria not in the stats, so only `:line` is enforced there.
#
# `:eval` is guarded on `coverage_for_eval_supported?` so the profile stays
# quiet on Ruby < 3.2, where enabling it would warn every time it loads.

SimpleCov.profiles.define "strict" do
  enable_coverage :branch
  enable_coverage :method
  # simplecov:disable branch — dogfood runs on Ruby >= 3.2 only, so
  # the else arm (eval coverage not supported) is unreachable from CI.
  enable_coverage :eval if coverage_for_eval_supported?
  # simplecov:enable
  minimum_coverage line: 100, branch: 100, method: 100
end
