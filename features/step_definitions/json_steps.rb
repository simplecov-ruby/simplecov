# frozen_string_literal: true

Then /^the JSON coverage report should match the output for the basic case$/ do
  cd(".") do
    json_report = JSON.parse(File.read("coverage/coverage.json"))
    coverage_hash = json_report.fetch "coverage"
    directory = Dir.pwd

    expect(coverage_hash.fetch("#{directory}/lib/faked_project.rb")).to eq "lines" => [nil, nil, 1, 1, 1, nil, nil, nil, 5, 3, nil, nil, 1]
    expect(coverage_hash.fetch("#{directory}/lib/faked_project/some_class.rb")).to eq "lines" => [nil, nil, 1, 1, 1, nil, 1, 2, nil, nil, 1, 1, nil, nil, 1, 1, 1, nil, 0, nil, nil, 0, nil, nil, 1, nil, 1, 0, nil, nil]
  end
end
