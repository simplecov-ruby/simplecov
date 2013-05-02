module SimpleCov

  class Report
    def generate(files)
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