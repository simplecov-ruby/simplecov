
Then /^a coverage report should have been generated(?: in "([^"]*)")?$/ do |coverage_dir|
  coverage_dir ||= 'coverage'
  steps %Q{
    Then the output should contain "Coverage report generated"
    And a directory named "#{coverage_dir}" should exist
    And the following files should exist:
      | #{coverage_dir}/index.html    |
      | #{coverage_dir}/resultset.yml |
  }
end

Then /^no coverage report should have been generated(?: in "([^"]*)")?$/ do |coverage_dir|
  coverage_dir ||= 'coverage'
  steps %Q{
    Then the output should not contain "Coverage report generated"
    And a directory named "#{coverage_dir}" should not exist
    And the following files should not exist:
      | #{coverage_dir}/index.html    |
      | #{coverage_dir}/resultset.yml |
  } 
end

Then /^the report should be based upon:$/ do |table|
  frameworks = table.raw.flatten
  steps %Q{
    Then the output should contain "Coverage report generated for #{frameworks.join(", ")}"
    And I should see "using #{frameworks.join(", ")}" within "#footer"
  }
end