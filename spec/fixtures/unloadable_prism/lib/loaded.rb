# frozen_string_literal: true

module Loaded
  def self.sign(number)
    number.negative? ? :negative : :non_negative
  end
end
