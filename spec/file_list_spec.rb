# frozen_string_literal: true

require "helper"

describe SimpleCov::FileList do
  subject(:file_list) do
    original_result = {
      source_fixture("sample.rb") => {
        "lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
        "branches" => {}
      },
      source_fixture("app/models/user.rb") => {
        "lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
        "branches" => {}
      },
      source_fixture("app/controllers/sample_controller.rb") => {
        "lines" => [nil, 2, 2, 0, nil, nil, 0, nil, nil, nil],
        "branches" => {}
      }
    }
    SimpleCov::Result.new(original_result).files
  end

  it "has 11 covered lines" do
    expect(file_list.covered_lines).to eq(11)
  end

  it "has 3 missed lines" do
    expect(file_list.missed_lines).to eq(3)
  end

  it "has 17 never lines" do
    expect(file_list.never_lines).to eq(17)
  end

  it "has 14 lines of code" do
    expect(file_list.lines_of_code).to eq(14)
  end

  it "has 5 skipped lines" do
    expect(file_list.skipped_lines).to eq(5)
  end

  it "has the correct covered percent" do
    expect(file_list.covered_percent).to eq(78.57142857142857)
  end

  it "has the correct covered percentages" do
    expect(file_list.covered_percentages).to eq([50.0, 80.0, 100.0])
  end

  it "has the correct least covered file" do
    expect(file_list.least_covered_file).to match(/sample_controller.rb/)
  end

  it "has the correct covered strength" do
    expect(file_list.covered_strength).to eq(0.9285714285714286)
  end
end
