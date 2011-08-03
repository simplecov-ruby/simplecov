
Then "a coverage report should have been generated" do
  steps %Q{
    Then the stdout should contain "Coverage report generated for Unit Tests"
    Then the following files should exist:
      | coverage/index.html    |
      | coverage/resultset.yml |
  }
end