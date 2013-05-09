require "algorithms"
require_relative "report"

module SimpleCov

  class AuthorReport < Report
    attr_reader :author_stats_mapping, :best_author_stats_mapping

    def initialize(options)
      @options = options
      @report_types = options[:report_types]

      # For each author, there is a mapping to a file/linesOfCode map
      # 'file/linesOfCode map': mapping from file name to the stats about coverage for code
      @author_stats_mapping = {}
      @best_author_stats_mapping = {}
    end

    def generate(files)
      compute_author_stats_mapping(files)
      if @report_types[:best_authors]
        compute_best_authors
      end

      @report = {
        :type => {
          :main => :author_report,
        },
        :sub_reports => []
      }

      if @report_types[:best_authors]
        @report[:sub_reports] <<
          {
            :type => :best_authors,
            :title => "Best Authors",
            :items => @best_author_stats_mapping
          }
      end

      if @report_types[:author_stats]
        @report[:sub_reports] <<
          {
            :type => :author_stats,
            :title => "Author Stats",
            :items => @author_stats_mapping
          }
      end

      @report
    end

    private
    def compute_author_stats_mapping(files)
      files.each do |file|
        file.lines.each do |line|
          next if line.author.nil? || line.date.nil?
          next if(line.date < Time.parse(@options[:author_report_from]) ||
            line.date > Time.parse(@options[:author_report_to]))

          @author_stats_mapping[line.author] = @author_stats_mapping[line.author] || {}
          files_stats = @author_stats_mapping[line.author][:files] =
            @author_stats_mapping[line.author][:files] || ItemMap.new
          files_stats[file] =
            files_stats[file] || {}

          if line.missed?
            files_stats[file][:missed] =
              files_stats[file][:missed] || 0
            files_stats[file][:missed] += 1
          elsif line.covered?
            files_stats[file][:covered] =
              files_stats[file][:covered] || 0
            files_stats[file][:covered] += 1
          end
        end

        @author_stats_mapping.keys.each do |author_name|
          files_stats = @author_stats_mapping[author_name][:files]
          next if files_stats[file].nil?
          files_stats[file][:covered] =
            files_stats[file][:covered] || 0
          files_stats[file][:missed] =
            files_stats[file][:missed] || 0

          if files_stats[file][:covered] == 0 &&
            files_stats[file][:missed] == 0
            files_stats.delete(file)
            next
          end

          files_stats[file][:total] =
            files_stats[file][:covered] +
              files_stats[file][:missed]
          files_stats[file][:coverage] =
            compute_coverage(files_stats[file])
        end
      end

      @author_stats_mapping.keys.each do |author_name|
        total_lines = 0
        total_covered_lines = 0

        author_stats = @author_stats_mapping[author_name]
        author_stats[:files].keys.each do |file|
          total_lines += author_stats[:files][file][:missed] +
            author_stats[:files][file][:covered]
          total_covered_lines += author_stats[:files][file][:covered]
        end
        author_stats[:total_coverage] = {}
        author_stats[:total_coverage][:missed] = total_lines - total_covered_lines
        author_stats[:total_coverage][:covered] = total_covered_lines
        author_stats[:total_coverage][:total] =
          author_stats[:total_coverage][:missed] +
            author_stats[:total_coverage][:covered]
        author_stats[:total_coverage][:coverage] =
          compute_coverage(author_stats[:total_coverage])
      end

      @author_stats_mapping
    end # compute_author_stats_mapping

    def compute_coverage(file_stats)
      return 0 if file_stats[:total] == 0
      100 * file_stats[:covered].to_f / file_stats[:total]
    end

    def compute_best_authors
      all_authors_queue = Containers::PriorityQueue.new
      significant_authors_queue = Containers::PriorityQueue.new

      @author_stats_mapping.keys.each do |author_name|
        author_stats = @author_stats_mapping[author_name]
        all_authors_queue.push(author_name, author_stats[:total_coverage][:total])
      end

      most_total_author = all_authors_queue.pop
      return if most_total_author.nil?
      significant_authors_queue.push(most_total_author,
                                     @author_stats_mapping[most_total_author][:total_coverage][:coverage])
      author_count = 1
      while (author_name = all_authors_queue.pop) != nil &&
        (
        comparable( @author_stats_mapping[most_total_author][:total_coverage][:total],
                    @author_stats_mapping[author_name][:total_coverage][:total]
        ) ||
          (
          comparable_cutoff( @author_stats_mapping[most_total_author][:total_coverage][:total],
                             @author_stats_mapping[author_name][:total_coverage][:total]
          ) &&
            author_count < @options[:best_authors_count]
          )
        )
        significant_authors_queue.push(author_name,
                                       @author_stats_mapping[author_name][:total_coverage][:coverage])
        author_count += 1
      end

      author_count = 0
      while (author_name = significant_authors_queue.pop) != nil &&
        author_count < @options[:best_authors_count]
        @best_author_stats_mapping[author_name] = @author_stats_mapping[author_name]
        author_count += 1
      end
    end # compute_best_authors

    def comparable(baseline, candidate)
      candidate.to_f / baseline * 100 >= @options[:best_author_tolerance]
    end

    def comparable_cutoff(baseline, candidate)
      candidate.to_f / baseline * 100 >= @options[:best_author_cutoff]
    end

  end # class AuthorReport

end # module SimpleCov