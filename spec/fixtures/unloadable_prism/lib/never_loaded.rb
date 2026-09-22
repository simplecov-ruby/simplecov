# frozen_string_literal: true

module NeverLoaded
  def self.sign(number)
    number.negative? ? :negative : :non_negative
  end
end
