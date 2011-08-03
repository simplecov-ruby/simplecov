
Then "a coverage report should have been generated" do
  steps %Q{
    Then the output should contain "Coverage report generated"
    And a directory named "coverage" should exist
    And the following files should exist:
      | coverage/index.html    |
      | coverage/resultset.yml |
  }
end

Then "no coverage report should have been generated" do
  steps %Q{
    Then the output should not contain "Coverage report generated"
    And a directory named "coverage" should not exist
    And the following files should not exist:
      | coverage/index.html    |
      | coverage/resultset.yml |
  } 
end