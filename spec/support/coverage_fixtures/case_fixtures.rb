# frozen_string_literal: true

# Coverage hashes for fixture scripts that primarily exercise case/when
# and the implicit-else behavior Ruby's Coverage library reports.
module CoverageFixtures
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
end
