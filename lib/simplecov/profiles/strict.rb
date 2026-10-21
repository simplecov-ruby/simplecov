# frozen_string_literal: true

# Every coverage criterion the runtime can measure, held to 100%. An opt-in
# profile rather than the default (#1061), so a team that has paid down the debt
# can flip the strict switch without re-typing the threshold trio every time.
#
# Each criterion is guarded on support, so on JRuby, which measures only lines,
# the profile neither asks `Coverage.start` for criteria it would warn about nor
# pins thresholds for them.

SimpleCov.profiles.define "strict" do
  enable_coverage :branch if branch_coverage_supported?
  enable_coverage :method if method_coverage_supported?
  # simplecov:disable branch — dogfood branch coverage runs on CRuby only,
  # so the else arm (eval coverage not supported) is unreachable from CI.
  enable_coverage :eval if coverage_for_eval_supported?
  # simplecov:enable
  minimum_coverage coverage_criteria.to_h { |criterion| [criterion, 100] }
end
