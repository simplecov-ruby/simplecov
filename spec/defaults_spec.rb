# frozen_string_literal: true

require "helper"

describe SimpleCov do
  skip "requires the default configuration" if ENV["SIMPLECOV_NO_DEFAULTS"]

  context "when profiles" do
    let(:config_class) do
      Class.new do
        include SimpleCov::Configuration

        def load_profile(name)
          configure(&SimpleCov.profiles[name.to_sym])
        end
      end
    end

    let(:config) { config_class.new }

    def filtered?(config, filename)
      path = File.join(SimpleCov.root, filename)
      file = SimpleCov::SourceFile.new(path, [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
      config.filters.any? { |filter| filter.matches?(file) }
    end

    it "provides a sensible test_frameworks profile" do
      config.load_profile(:test_frameworks)
      expect(filtered?(config, "foo.rb")).to be_falsey
      expect(filtered?(config, "test/foo.rb")).to be_truthy
      expect(filtered?(config, "spec/bar.rb")).to be_truthy
    end

    it "provides a sensible rails profile" do
      config.load_profile(:rails)
      expect(filtered?(config, "app/models/user.rb")).to be_falsey
      expect(filtered?(config, "db/schema.rb")).to be_truthy
      expect(filtered?(config, "config/environment.rb")).to be_truthy
    end
  end
end
