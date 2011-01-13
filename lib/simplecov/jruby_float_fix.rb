# Temporary fix for JRuby 1.6.0 RC1 wrong round method
if defined?(RUBY_ENGINE) and RUBY_ENGINE == 'jruby' and RUBY_VERSION == '1.9.2'
  class Float
    alias_method :precisionless_round, :round
    def round(precision = nil)
      if precision
        magnitude = 10.0 ** precision
        (self * magnitude).round / magnitude
      else
        precisionless_round
      end
    end
  end
end