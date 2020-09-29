# frozen_string_literal: true

Then /^the JSON coverage report should map:/ do |expected_report|
  cd(".") do
    json_report = File.open("coverage/coverage.json").read
    expected_report = ERB.new(expected_report).result(binding)
    expect(json_report).to eq(expected_report)
  end
end
