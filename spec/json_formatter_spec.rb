# frozen_string_literal: true

require "helper"

require "simplecov/formatter/json_formatter"

describe SimpleCov::Formatter::JSONFormatter do
  let(:result) do
    SimpleCov::Result.new({
                            source_fixture("json/sample.rb") => {"lines" => [
                              nil, 1, 1, 1, 1, nil, nil, 1, 1, nil, nil,
                              1, 1, 0, nil, 1, nil, nil, nil, nil, 1, 0, nil, nil, nil
                            ]}
                          })
  end

  describe "format" do
    context "with line coverage" do
      it "works" do
        subject.format(result, verbose: false)
        expect(json_ouput).to eq(json_result("sample"))
      end
    end

    context "with branch coverage" do
      let(:original_lines) do
        [nil, 1, 1, 1, 1, nil, nil, 1, 1,
         nil, nil, 1, 1, 0, nil, 1, nil,
         nil, nil, nil, 1, 0, nil, nil, nil]
      end

      let(:original_branches) do
        {
          [:if, 0, 13, 4, 17, 7] => {
            [:then, 1, 14, 6, 14, 10] => 0,
            [:else, 2, 16, 6, 16, 10] => 1
          }
        }
      end

      let(:result) do
        SimpleCov::Result.new({
                                source_fixture("json/sample.rb") => {
                                  "lines" => original_lines,
                                  "branches" => original_branches
                                }
                              })
      end

      before do
        enable_branch_coverage
      end

      it "works" do
        subject.format(result, verbose: false)
        expect(json_ouput).to eq(json_result("sample_with_branch"))
      end
    end

    context "with groups" do
      let(:result) do
        res = SimpleCov::Result.new({
                                      source_fixture("json/sample.rb") => {"lines" => [
                                        nil, 1, 1, 1, 1, nil, nil, 1, 1, nil, nil,
                                        1, 1, 0, nil, 1, nil, nil, nil, nil, 1, 0, nil, nil, nil
                                      ]}
                                    })

        # right now SimpleCov works mostly on global state, hence setting the groups that way
        # would be global state --> Mocking is better here
        allow(res).to receive_messages(groups: {"My Group" => double("File List", covered_percent: 80.0)})
        res
      end

      it "displays groups correctly in the JSON" do
        subject.format(result, verbose: false)
        expect(json_ouput).to eq(json_result("sample_groups"))
      end
    end
  end

  def enable_branch_coverage
    allow(SimpleCov).to receive(:branch_coverage?).and_return(true)
  end

  def json_ouput
    JSON.parse(File.read("tmp/coverage/coverage.json"))
  end

  def json_result(filename)
    file = File.read(source_fixture("json/#{filename}.json"))
    file = use_current_working_directory(file)
    JSON.parse(file)
  end

  DEFAULT_WORKING_DIRECTORY = "STUB_WORKING_DIRECTORY"
  def use_current_working_directory(file)
    current_working_directory = File.expand_path("..", File.dirname(__FILE__))
    file.gsub!("/#{DEFAULT_WORKING_DIRECTORY}/", "#{current_working_directory}/")

    file
  end
end
