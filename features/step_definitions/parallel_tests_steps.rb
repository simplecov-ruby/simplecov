# frozen_string_literal: true

Then "I should see the results for the parallel tests project" do
  steps %(
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 89.36%   | 9     |
    And I should see the source files:
      | name            | coverage |
      | lib/all.rb      | 100.0 %  |
      | spec/a_spec.rb  | 100.0 %  |
      | spec/b_spec.rb  | 100.0 %  |
      | spec/c_spec.rb  | 100.0 %  |
      | spec/d_spec.rb  | 100.0 %  |
      | lib/a.rb        | 85.71 %  |
      | lib/b.rb        | 80.0 %   |
      | lib/c.rb        | 75.0 %   |
      | lib/d.rb        | 71.43 %  |
  )
end
