module SimpleCov
  module JSON
    class << self
      def adapter=(adapter)
        @adapter = adapter
      end
      def adapter
        @adapter ||= self.adapter = begin
                                      multi_json_adapter
                                    rescue LoadError
                                      require 'json'
                                      ::JSON
                                    end
      end
      def parse(json)
        adapter.load(json)
      end

      def dump(string)
        adapter.dump(string)
      end

      def multi_json_adapter
        @multi_json_adapter ||= begin
                                  require 'multi_json'
                                  ::MultiJson
                                end
      end
    end
  end
end
