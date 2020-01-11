# frozen_string_literal: true

Then "I should see the results for the parallel tests project" do
  steps %(
    Then I should see the groups:
      | name      | coverage | files |
      | All Files | 89.36%   | 9     |
  )
end
