module SimpleCov

  class Report
    def generate(files)
    end

    class << self
      attr_reader :report_types

      def register(report_type_identifier, report_type)
        @report_types = @report_types || {}
        @report_types[report_type_identifier] = report_type
      end
    end

    class ItemMap < Hash
      def to_json(options)
        map = {}
        self.each do |file, report|
          map[file.filename] = report
        end
        map.to_json
      end
    end

  end # Report

end # SimpleCov