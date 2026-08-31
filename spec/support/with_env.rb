# frozen_string_literal: true

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
