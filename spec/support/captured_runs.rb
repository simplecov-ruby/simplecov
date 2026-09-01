# frozen_string_literal: true

# Spawning a process costs about fifteen times more on JRuby than on CRuby, so
# specs that shell out dominate the JRuby suite. Where several examples only
# read back the result of one identical invocation, they share a single capture
# from here rather than each paying for its own.
module CapturedRuns
  class << self
    def once(key)
      cache.fetch(key) { cache[key] = yield }
    end

    private

    def cache
      @cache ||= {}
    end
  end
end
