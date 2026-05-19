# frozen_string_literal: true

Then "I should see the line coverage results for the parallel tests project" do
  steps %(
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 81.48%   | 5     |
    And I should see the source files:
      | name            | coverage |
      | lib/all.rb      | 100.00%  |
      | lib/a.rb        | 85.71%   |
      | lib/b.rb        | 80.00%   |
      | lib/c.rb        | 75.00%   |
      | lib/d.rb        | 71.42%   |
  )
end

Then "I should see the branch coverage results for the parallel tests project" do
  steps %(
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 81.48%   | 5     |
    And I should see a line coverage summary of 22/27
    And I should see a branch coverage summary of 4/8
    And I should see the source files:
      | name            | coverage | branch coverage |
      | lib/all.rb      | 100.00%  | 100.00%         |
      | lib/a.rb        | 85.71%   | 50.00%          |
      | lib/b.rb        | 80.00%   | 100.00%         |
      | lib/c.rb        | 75.00%   | 50.00%          |
      | lib/d.rb        | 71.42%   | 50.00%          |
  )
end
