# frozen_string_literal: true

SimpleCov.profiles.define "test_frameworks" do
  add_filter %r{\A(test|features|spec|autotest)/}
end
