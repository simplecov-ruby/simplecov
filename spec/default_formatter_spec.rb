# frozen_string_literal: true

require "helper"
require "simplecov_json_formatter"

describe SimpleCov::Formatter do
  describe ".from_env" do
    let(:env) { {"QLTY_COVERAGE_TOKEN" => "4c9f1de6193f30799e9a5d5c082692abecc1fd2c6aa62c621af7b2a910761970"} }

    context "when QLTY_COVERAGE_TOKEN environment variable is set" do
      it "returns an array containing the HTML and JSON formatters" do
        expect(described_class.from_env(env)).to eq([
                                                      SimpleCov::Formatter::HTMLFormatter,
                                                      SimpleCov::Formatter::JSONFormatter
                                                    ])
      end
    end

    context "when QLTY_COVERAGE_TOKEN environment variable isn't set" do
      let(:env) { {} }

      it "returns an array containing only the HTML formatter" do
        expect(described_class.from_env(env)).to eq([
                                                      SimpleCov::Formatter::HTMLFormatter
                                                    ])
      end
    end
  end
end
