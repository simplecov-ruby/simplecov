# frozen_string_literal: true

module Monorepo
  class Base
    def initialize(label)
      @label = label
    end

    def reverse
      @label.reverse
    end
  end
end
