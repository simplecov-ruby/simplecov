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
                                  # Detect and patch available MultiJson API - it changed in v1.3
                                  unless ::MultiJson.respond_to?(:adapter)
                                    ::MultiJson.module_eval do
                                      alias_method :load, :decode unless respond_to?(:load)
                                      alias_method :dump, :encode unless respond_to?(:dump)
                                    end
                                  end
                                  ::MultiJson
                                end
      end
    end
  end
end
