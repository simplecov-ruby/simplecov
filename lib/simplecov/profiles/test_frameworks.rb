# frozen_string_literal: true

SimpleCov.profiles.define "test_frameworks" do
  add_filter %r{^/(test|features|spec|autotest)/}
end
