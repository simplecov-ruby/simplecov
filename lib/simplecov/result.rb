require "digest/sha1"
require "forwardable"

module SimpleCov
  #
  # A simplecov code coverage result, initialized from the Hash Ruby 1.9's built-in coverage
  # library generates (Coverage.result).
  #
  class Result
    extend Forwardable
    # Returns the original Coverage.result used for this instance of SimpleCov::Result
    attr_reader :original_result
    # Returns all files that are applicable to this result (sans filters!) as instances of SimpleCov::SourceFile. Aliased as :source_files
    attr_reader :files
    alias source_files files
    # Explicitly set the Time this result has been created
    attr_writer :created_at
    # Explicitly set the command name that was used for this coverage result. Defaults to SimpleCov.command_name
    attr_writer :command_name

    def_delegators :files, :covered_percent, :covered_percentages, :least_covered_file, :covered_strength, :covered_lines, :missed_lines
    def_delegator :files, :lines_of_code, :total_lines

    # Initialize a new SimpleCov::Result from given Coverage.result (a Hash of filenames each containing an array of
    # coverage data)
    def initialize(original_result)
      @original_result = original_result.freeze
      @files = SimpleCov::FileList.new(original_result.map do |filename, coverage|
        SimpleCov::SourceFile.new(filename, coverage) if File.file?(filename)
      end.compact.sort_by(&:filename)).group_by do |file|
        File.read(file.filename).hash
      end.map do |_, files|
        files.reduce(nil) do |acc, file|
          next file unless acc
          combine_files(acc, file)
        end
      end
      filter!
    end

    # Returns all filenames for source files contained in this result
    def filenames
      files.map(&:filename)
    end

    # Returns a Hash of groups for this result. Define groups using SimpleCov.add_group 'Models', 'app/models'
    def groups
      @groups ||= SimpleCov.grouped(files)
    end

    # Applies the configured SimpleCov.formatter on this result
    def format!
      SimpleCov.formatter.new.format(self)
    end

    # Defines when this result has been created. Defaults to Time.now
    def created_at
      @created_at ||= Time.now
    end

    # The command name that launched this result.
    # Delegated to SimpleCov.command_name if not set manually
    def command_name
      @command_name ||= SimpleCov.command_name
    end

    # Returns a hash representation of this Result that can be used for marshalling it into JSON
    def to_hash
      {command_name => {"coverage" => coverage, "timestamp" => created_at.to_i}}
    end

    # Loads a SimpleCov::Result#to_hash dump
    def self.from_hash(hash)
      command_name, data = hash.first
      result = SimpleCov::Result.new(data["coverage"])
      result.command_name = command_name
      result.created_at = Time.at(data["timestamp"])
      result
    end

  private

    # Combine files that are the same (have same content) but have different file paths
    def combine_files(file1, file2)
      new_coverage = combine_coverages(file1.coverage, file2.coverage)
      # NOTE: It is possible that both don't exist but eventually either one does or it's just one of the names that was
      # used in the code
      new_filename = strict_file_exists?(file1.filename) ? file1.filename : file2.filename
      SimpleCov::SourceFile.new(new_filename, new_coverage)
    end

    # Does a case-sensitive check for file, unlike File.exists?
    def strict_file_exists?(path)
      directory = `dirname #{path}`.chomp
      name = `basename #{path}`.chomp
      !`find "#{directory}" -name "#{name}"`.empty?
    end

    # This method combines coverages from the same file but spelled differently
    def combine_coverages(coverage1, coverage2)
      raise ArgumentError, "size of coverages are not equal" if coverage1.size != coverage2.size
      coverage1.map.with_index do |number, index|
        number2 = coverage2[index] || 0
        number ||= 0
        number + number2
      end
    end

    def coverage
      keys = original_result.keys & filenames
      Hash[keys.zip(original_result.values_at(*keys))]
    end

    # Applies all configured SimpleCov filters on this result's source files
    def filter!
      @files = SimpleCov.filtered(files)
    end
  end
end
