# frozen_string_literal: true

require "monorepo/base"

module Monorepo
  class Extra
    def initialize(label)
      @label = label
    end

    def identity
      Base.new(Base.new(@label).reverse).reverse
    end
  end
end
