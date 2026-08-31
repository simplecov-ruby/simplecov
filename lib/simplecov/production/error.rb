# frozen_string_literal: true

module SimpleCov
  module Production
    # Configuration and store-format failures. Sink errors raised from `store` are
    # not wrapped in this: the runtime rescues them, warns, and retries on the
    # next interval.
    class Error < StandardError
    end
  end
end
