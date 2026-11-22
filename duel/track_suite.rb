# frozen_string_literal: true

# A suite of TESTS tests run under `track_tests`, as `duel/track_duel.rb`
# starts it in a process of its own. Coverage is started here, by
# SimpleCov, so the criteria SimpleCov asks Coverage for are measured too:
# every criterion makes each of a test's two snapshots copy more.

require_relative "duel_helper"

FILES = 200
TESTS = 250

root, paths = DuelFixtures.callable_project(FILES)

require "simplecov"
SimpleCov.root(root)
SimpleCov.track_tests
SimpleCov.start_tracking
paths.each { |path| require path }

models = Array.new(FILES) { |index| Object.const_get(:"DuelModel#{index}") }
TESTS.times do |test|
  SimpleCov.track_test("spec/models/model_spec.rb[1:#{test + 1}]") do
    DuelFixtures::FILES_A_TEST_TOUCHES.times do |touched|
      model = models.fetch((test * 7 + touched * (FILES / DuelFixtures::FILES_A_TEST_TOUCHES)) % FILES).new(test.to_s)
      model.label_0
      model.present_1?
      model.total_2(test)
    end
  end
end

# Leave without SimpleCov's at_exit, which would write a resultset, and
# measure only the tests.
exit!(0)
