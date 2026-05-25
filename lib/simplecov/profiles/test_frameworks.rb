# frozen_string_literal: true

SimpleCov.profiles.define "test_frameworks" do
  skip %r{\A(test|features|spec|autotest)/}
end
