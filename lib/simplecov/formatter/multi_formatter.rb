class SimpleCov::Formatter::MultiFormatter
  def self.[](*args)
    Class.new(self) do
      define_method :formatters do
        @formatters ||= args
      end
    end
  end

  def format(result)
    formatters.map do |formatter|
      formatter.new.format(result)
    end
  end

  def formatters
    @formatters ||= []
  end

end
