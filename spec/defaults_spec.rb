require "helper"

if SimpleCov.usable?
  describe SimpleCov do
    skip "requires the default configuration" if ENV["SIMPLECOV_NO_DEFAULTS"]

    context "profiles" do
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
        expect(filtered?(config, "foo.rb")).not_to be
        expect(filtered?(config, "test/foo.rb")).to be
        expect(filtered?(config, "spec/bar.rb")).to be
      end

      it "provides a sensible rails profile" do
        config.load_profile(:rails)
        expect(filtered?(config, "app/models/user.rb")).not_to be
        expect(filtered?(config, "db/schema.rb")).to be
        expect(filtered?(config, "config/environment.rb")).to be
      end
    end
  end
end
