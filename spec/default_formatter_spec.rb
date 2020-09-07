# frozen_string_literal: true

require "helper"
require "simplecov_json_formatter"

describe SimpleCov::Formatter do
  describe ".from_env" do
    context "when CC_TEST_REPORTER_ID environment variable is set" do
      before do
        ENV["CC_TEST_REPORTER_ID"] = "4c9f1de6193f30799e9a5d5c082692abecc1fd2c6aa62c621af7b2a910761970"
      end

      it "returns a MultiFormatter instance with the HTML and JSON formatter" do
        expect(SimpleCov::Formatter::MultiFormatter).to receive(:new).with([
                                                                             SimpleCov::Formatter::HTMLFormatter,
                                                                             SimpleCov::Formatter::JSONFormatter
                                                                           ])

        described_class.from_env
      end
    end

    context "when CC_TEST_REPORTER_ID environment variable isn't set" do
      before do
        ENV["CC_TEST_REPORTER_ID"] = nil
      end

      it "returns a MultiFormatter instance with the HTML and JSON formatter" do
        expect(SimpleCov::Formatter::MultiFormatter).to receive(:new).with([
                                                                             SimpleCov::Formatter::HTMLFormatter
                                                                           ])

        described_class.from_env
      end
    end
  end
end
