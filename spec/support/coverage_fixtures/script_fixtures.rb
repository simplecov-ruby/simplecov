# frozen_string_literal: true

# Coverage hashes for fixture scripts that primarily exercise nocov
# handling, eval-attributed coverage, and miscellaneous shapes.
module CoverageFixtures
  SAMPLE_RB = {
    "lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, nil, nil, nil, nil, nil]
  }.freeze

  NEVER_RB = {"lines" => [nil, nil], "branches" => {}}.freeze

  NOCOV_COMPLEX_RB = {
    "lines" => [
      nil, nil, 1, 1, nil, 1, nil, nil, nil, 1, nil, nil, 1, nil,
      nil, 0, nil, 1, nil, 0, nil, nil, 1, nil, nil, nil, nil
    ],
    "branches" => {
      [:if, 0, 6, 4, 11, 7] => {[:then, 1, 7, 6, 7, 7] => 0, [:else, 2, 10, 6, 10, 7] => 1},
      [:if, 3, 13, 4, 13, 24] => {[:then, 4, 13, 4, 13, 12] => 1, [:else, 5, 13, 4, 13, 24] => 0},
      [:while, 6, 16, 4, 16, 27] => {[:body, 7, 16, 4, 16, 12] => 2},
      [:case, 8, 18, 4, 24, 7] => {
        [:when, 9, 20, 6, 20, 11] => 0,
        [:when, 10, 23, 6, 23, 10] => 1,
        [:else, 11, 18, 4, 24, 7] => 0
      }
    }
  }.freeze

  SINGLE_NOCOV_RB = {
    "lines" => [nil, 1, 1, 1, 0, 1, 0, 1, 1, nil, 0, nil, nil, nil],
    "branches" => {
      [:if, 0, 8, 4, 11, 10] => {[:then, 1, 9, 6, 9, 10] => 1, [:else, 2, 11, 6, 11, 10] => 0},
      [:if, 3, 6, 4, 11, 10] => {[:then, 4, 7, 6, 7, 10] => 0, [:else, 5, 8, 4, 11, 10] => 1},
      [:if, 6, 4, 4, 12, 7] => {[:then, 7, 5, 6, 5, 10] => 0, [:else, 8, 6, 4, 11, 10] => 1}
    }
  }.freeze

  UNEVEN_NOCOVS_RB = {
    "lines" => [1, 1, nil, 1, 0, 1, 0, nil, 1, 1, nil, nil, 0, nil, nil, nil],
    "branches" => {
      [:if, 0, 9, 4, 13, 10] => {[:then, 1, 10, 6, 10, 10] => 1, [:else, 2, 13, 6, 13, 10] => 0},
      [:if, 3, 6, 4, 13, 10] => {[:then, 4, 7, 6, 7, 10] => 0, [:else, 5, 9, 4, 13, 10] => 1},
      [:if, 6, 4, 4, 14, 7] => {[:then, 7, 5, 6, 5, 10] => 0, [:else, 8, 6, 4, 13, 10] => 1}
    }
  }.freeze

  # Mimics what Ruby's `Coverage` reports for a file that uses an
  # eval-based macro (e.g., Rails' `delegate` or `def_delegators`). The
  # eval-generated method (`:hello`) and the branch inside its body get
  # attributed to the macro's source line (line 2 here), even though
  # there's no real `def hello` or `if`/`case`/etc. at that line in the
  # static source. `ignore_methods :eval_generated` and
  # `ignore_branches :eval_generated` use Prism to recognize and drop
  # those entries. See #1046.
  EVAL_GENERATED_RB = {
    "lines" => [nil, 1, 1, 1, nil, 1, nil, nil],
    "branches" => {
      # Eval-generated `:if` attributed to the def_delegators call line.
      [:if, 0, 2, 2, 2, 35] => {[:then, 1, 2, 2, 2, 35] => 1, [:else, 2, 2, 2, 2, 35] => 0},
      # Real `:if` inside `initialize` (line 4, hypothetical body branch).
      [:if, 3, 4, 4, 4, 24] => {[:then, 4, 4, 4, 4, 24] => 1, [:else, 5, 4, 4, 4, 24] => 0}
    },
    "methods" => {
      # Eval-generated method at the def_delegators call line.
      ["EvalHost", :hello, 2, 2, 2, 35] => 1,
      # Real `def initialize` at line 3.
      ["EvalHost", :initialize, 3, 2, 5, 5] => 1
    }
  }.freeze
end
