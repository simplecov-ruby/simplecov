# frozen_string_literal: true

# Coverage data fixtures adapted from simplecov's spec/source_file_spec.rb
module CoverageFixtures
  BRANCHES_RB = {
    "lines" => [1, 1, 1, nil, 1, nil, 1, 0, nil, 1, nil, nil, nil],
    "branches" => {
      [:if, 0, 3, 4, 3, 21] => {[:then, 1, 3, 4, 3, 10] => 0, [:else, 2, 3, 4, 3, 21] => 1},
      [:if, 3, 5, 4, 5, 26] => {[:then, 4, 5, 16, 5, 20] => 1, [:else, 5, 5, 23, 5, 26] => 0},
      [:if, 6, 7, 4, 11, 7] => {[:then, 7, 8, 6, 8, 10] => 0, [:else, 8, 10, 6, 10, 9] => 1}
    }
  }.freeze

  SAMPLE_RB = {
    "lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, nil, nil, nil, nil, nil, nil]
  }.freeze

  INLINE_RB = {
    "lines" => [1, 1, 1, nil, 1, 1, 0, nil, 1, nil, nil, nil, nil],
    "branches" => {
      [:if, 0, 3, 11, 3, 33] => {[:then, 1, 3, 23, 3, 27] => 1, [:else, 2, 3, 30, 3, 33] => 0},
      [:if, 3, 6, 6, 10, 9] => {[:then, 4, 7, 8, 7, 12] => 0, [:else, 5, 9, 8, 9, 11] => 1}
    }
  }.freeze

  NEVER_RB = {"lines" => [nil, nil], "branches" => {}}.freeze

  NOCOV_COMPLEX_RB = {
    "lines" => [nil, nil, 1, 1, nil, 1, nil, nil, nil, 1, nil, nil, 1, nil, nil, 0, nil, 1, nil, 0, nil, nil, 1, nil, nil, nil, nil],
    "branches" => {
      [:if, 0, 6, 4, 11, 7] => {[:then, 1, 7, 6, 7, 7] => 0, [:else, 2, 10, 6, 10, 7] => 1},
      [:if, 3, 13, 4, 13, 24] => {[:then, 4, 13, 4, 13, 12] => 1, [:else, 5, 13, 4, 13, 24] => 0},
      [:while, 6, 16, 4, 16, 27] => {[:body, 7, 16, 4, 16, 12] => 2},
      [:case, 8, 18, 4, 24, 7] => {[:when, 9, 20, 6, 20, 11] => 0, [:when, 10, 23, 6, 23, 10] => 1, [:else, 11, 18, 4, 24, 7] => 0}
    }
  }.freeze

  NESTED_BRANCHES_RB = {
    "lines" => [nil, nil, 1, 1, 1, 1, 1, 1, nil, nil, 0, nil, nil, nil, nil],
    "branches" => {
      [:while, 0, 7, 8, 7, 31] => {[:body, 1, 7, 8, 7, 16] => 2},
      [:if, 2, 6, 6, 9, 9] => {[:then, 3, 7, 8, 8, 11] => 1, [:else, 4, 6, 6, 9, 9] => 0},
      [:if, 5, 5, 4, 12, 7] => {[:then, 6, 6, 6, 9, 9] => 1, [:else, 7, 11, 6, 11, 11] => 0}
    }
  }.freeze

  CASE_RB = {
    "lines" => [1, 1, 1, nil, 0, nil, 1, nil, 0, nil, 0, nil, nil, nil],
    "branches" => {
      [:case, 0, 3, 4, 12, 7] => {
        [:when, 1, 5, 6, 5, 10] => 0, [:when, 2, 7, 6, 7, 10] => 1,
        [:when, 3, 9, 6, 9, 10] => 0, [:else, 4, 11, 6, 11, 11] => 0
      }
    }
  }.freeze

  CASE_WITHOUT_ELSE_RB = {
    "lines" => [1, 1, 1, nil, 0, nil, 1, nil, 0, nil, nil, nil],
    "branches" => {
      [:case, 0, 3, 4, 10, 7] => {
        [:when, 1, 5, 6, 5, 10] => 0, [:when, 2, 7, 6, 7, 10] => 1,
        [:when, 3, 9, 6, 9, 10] => 0, [:else, 4, 3, 4, 10, 7] => 0
      }
    }
  }.freeze

  ELSIF_RB = {
    "lines" => [1, 1, 1, 0, 1, 0, 1, 1, nil, 0, nil, nil, nil],
    "branches" => {
      [:if, 0, 7, 4, 10, 10] => {[:then, 1, 8, 6, 8, 10] => 1, [:else, 2, 10, 6, 10, 10] => 0},
      [:if, 3, 5, 4, 10, 10] => {[:then, 4, 6, 6, 6, 10] => 0, [:else, 5, 7, 4, 10, 10] => 1},
      [:if, 6, 3, 4, 11, 7] => {[:then, 7, 4, 6, 4, 10] => 0, [:else, 8, 5, 4, 10, 10] => 1}
    }
  }.freeze

  BRANCH_TESTER_RB = {
    "lines" => [nil, nil, 1, 1, nil, 1, nil, 1, 1, nil, nil, 1, 0, nil, nil, 1, 0, nil, 1, nil, nil, 1, 1, 1, nil, nil, 1, 0, nil, nil, 1, 1, nil, 0, nil, 1,
                1, 0, 0, 1, 5, 0, 0, nil, 0, nil, 0, nil, nil, nil],
    "branches" => {
      [:if, 0, 4, 0, 4, 19] => {[:then, 1, 4, 12, 4, 15] => 0, [:else, 2, 4, 18, 4, 19] => 1},
      [:unless, 3, 6, 0, 6, 23] => {[:else, 4, 6, 0, 6, 23] => 0, [:then, 5, 6, 0, 6, 6] => 1},
      [:unless, 6, 8, 0, 10, 3] => {[:else, 7, 8, 0, 10, 3] => 0, [:then, 8, 9, 2, 9, 14] => 1},
      [:unless, 9, 12, 0, 14, 3] => {[:else, 10, 12, 0, 14, 3] => 1, [:then, 11, 13, 2, 13, 14] => 0},
      [:unless, 12, 16, 0, 20, 3] => {[:else, 13, 19, 2, 19, 13] => 1, [:then, 14, 17, 2, 17, 14] => 0},
      [:if, 15, 22, 0, 22, 19] => {[:then, 16, 22, 0, 22, 6] => 0, [:else, 17, 22, 0, 22, 19] => 1},
      [:if, 18, 23, 0, 25, 3] => {[:then, 19, 24, 2, 24, 14] => 1, [:else, 20, 23, 0, 25, 3] => 0},
      [:if, 21, 27, 0, 29, 3] => {[:then, 22, 28, 2, 28, 14] => 0, [:else, 23, 27, 0, 29, 3] => 1},
      [:if, 24, 31, 0, 35, 3] => {[:then, 25, 32, 2, 32, 14] => 1, [:else, 26, 34, 2, 34, 13] => 0},
      [:if, 27, 42, 0, 47, 8] => {[:then, 28, 43, 2, 45, 13] => 0, [:else, 29, 47, 2, 47, 8] => 0},
      [:if, 30, 40, 0, 47, 8] => {[:then, 31, 41, 2, 41, 25] => 1, [:else, 32, 42, 0, 47, 8] => 0},
      [:if, 33, 37, 0, 48, 3] => {[:then, 34, 38, 2, 39, 21] => 0, [:else, 35, 40, 0, 47, 8] => 1}
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
    "uneven_nocovs.rb" => UNEVEN_NOCOVS_RB
  }.freeze
end
