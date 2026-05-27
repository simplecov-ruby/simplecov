# frozen_string_literal: true

require_relative "coverage_fixtures/branch_fixtures"
require_relative "coverage_fixtures/case_fixtures"
require_relative "coverage_fixtures/script_fixtures"

# Aggregate index pairing each fixture script under spec/fixtures/ with
# the coverage hash the suite uses for it. Individual constants live in
# the sibling files under spec/support/coverage_fixtures/.
module CoverageFixtures
  ALL_FIXTURES = {
    "branches.rb" => BRANCHES_RB,
    "sample.rb" => SAMPLE_RB,
    "inline.rb" => INLINE_RB,
    "never.rb" => NEVER_RB,
    "nocov_complex.rb" => NOCOV_COMPLEX_RB,
    "nested_branches.rb" => NESTED_BRANCHES_RB,
    "case.rb" => CASE_RB,
    "case_without_else.rb" => CASE_WITHOUT_ELSE_RB,
    "elsif.rb" => ELSIF_RB,
    "branch_tester_script.rb" => BRANCH_TESTER_RB,
    "single_nocov.rb" => SINGLE_NOCOV_RB,
    "uneven_nocovs.rb" => UNEVEN_NOCOVS_RB,
    "eval_generated.rb" => EVAL_GENERATED_RB
  }.freeze
end
