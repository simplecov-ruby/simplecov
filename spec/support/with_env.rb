# frozen_string_literal: true

# Set ENV vars for the duration of a block, restoring the previous
# values (including absent) on exit, even on exception. Pass `nil` as
# a value to unset a key for the duration of the block.
#
# Avoids the spec-brittleness of stubbing `ENV[]` / `ENV.fetch` /
# `ENV.values_at` directly: the helper doesn't care which access
# method the implementation reaches for, so refactors that change the
# read shape (e.g. `ENV["X"]` → `ENV.values_at("X", "Y")`) don't
# require rewriting every test that exercises the env-driven branch.
#
#     with_env("TEST_ENV_NUMBER" => "1", "PARALLEL_TEST_GROUPS" => "2") do
#       expect(thing.guess).to eq("RSpec (1/2)")
#     end
module WithEnv
  def with_env(**vars)
    keys = vars.transform_keys(&:to_s)
    saved = keys.transform_values { |_| nil }
    keys.each_key { |k| saved[k] = ENV.fetch(k, nil) }
    keys.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved&.each { |k, v| ENV[k] = v }
  end
end

RSpec.configure do |config|
  config.include(WithEnv)
end
