require 'digest/sha1'
require 'yaml'

module SimpleCov
  # :nodoc:
  class FileWhitelist < Array
    def include?(arg)
      if count > 0
        super
      else
        true
      end
    end
  end

  #
  # A simplecov code coverage result, initialized from the Hash Ruby 1.9's built-in coverage
  # library generates (Coverage.result).
  #
  class Result
    # Returns the original Coverage.result used for this instance of SimpleCov::Result
    attr_reader :original_result
    # Returns all files that are applicable to this result (sans filters!) as instances of SimpleCov::SourceFile. Aliased as :source_files
    attr_reader :files
    attr_reader :file_whitelist # :nodoc:
    alias_method :source_files, :files
    # Explicitly set the Time this result has been created
    attr_writer :created_at
    # Explicitly set the command name that was used for this coverage result. Defaults to SimpleCov.command_name
    attr_writer :command_name

    # Initialize a new SimpleCov::Result from given Coverage.result (a Hash of filenames each containing an array of
    # coverage data)
    def initialize(original_result)
      @original_result = original_result.freeze
      @files = original_result.map {|filename, coverage|
        SimpleCov::SourceFile.new(filename, coverage) if File.file?(filename)
      }.compact.sort_by(&:filename)
      @file_whitelist = FileWhitelist.new
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

    # Set the list of files to include in subsequent coverage calculations. This is useful for determining
    # the coverage of a particular module / class / directory rather than the whole project.
    # The value can be a hash of filename -> bool mappings (filename is the key; truthy values get added
    # to the whitelist), a simple array of filenames, or a single filename string.
    def file_whitelist=(file_wl)
      reset_file_whitelist!
      if file_wl.is_a? Hash
        # hash of file -> bool mappings (true means the file is on the whitelist)
        file_wl.each_pair do |key, value|
          @file_whitelist << File.expand_path(key) if !!value
        end
      elsif file_wl.respond_to? :each
        # array-like substance
        file_wl.each do |path|
          @file_whitelist << File.expand_path(path)
        end
      elsif file_wl.is_a? String
        # one string
        @file_whitelist << File.expand_path(file_wl)
      end
    end

    # Reset the file whitelist to 'all files' (except any you are filtering)
    def reset_file_whitelist!
      @file_whitelist.clear
    end

    # The overall percentual coverage for this result
    def covered_percent
      # Make sure that weird rounding error from #15, #23 and #24 does not occur again!
      total_lines.zero? ? 0 : 100.0 * covered_lines / total_lines
    end

    # Returns the count of lines that are covered
    def covered_lines
      return @covered_lines if @covered_lines
      @covered_lines = 0
      @files.select { |f|
        @file_whitelist.include? f.filename
      }.each do |file|
        original_result[file.filename].each do |line_result|
          @covered_lines += 1 if line_result and line_result > 0
        end
      end
      @covered_lines
    end

    # Returns the count of missed lines
    def missed_lines
      return @missed_lines if @missed_lines
      @missed_lines = 0
      @files.select { |f|
        @file_whitelist.include? f.filename
      }.each do |file|
        original_result[file.filename].each do |line_result|
          @missed_lines += 1 if line_result == 0
        end
      end
      @missed_lines
    end

    # Total count of relevant lines (covered + missed)
    def total_lines
      @total_lines = Hash.new if @total_lines.nil?
      @total_lines[@file_whitelist] ||= (covered_lines + missed_lines)
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
    # Retrieved from SimpleCov.command_name
    def command_name
      @command_name ||= SimpleCov.command_name
    end

    # Returns a hash representation of this Result that can be used for marshalling it into YAML
    def to_hash
      {command_name => {:original_result => original_result.reject {|filename, result| !filenames.include?(filename) }, :created_at => created_at}}
    end

    # Returns a yaml dump of this result, which then can be reloaded using SimpleCov::Result.from_yaml
    def to_yaml
      to_hash.to_yaml
    end

    # Loads a SimpleCov::Result#to_hash dump
    def self.from_hash(hash)
      command_name, data = hash.first
      result = SimpleCov::Result.new(data[:original_result])
      result.command_name = command_name
      result.created_at = data[:created_at]
      result
    end

    # Loads a SimpleCov::Result#to_yaml dump
    def self.from_yaml(yaml)
      from_hash(YAML.load(yaml))
    end

    private

    # Applies all configured SimpleCov filters on this result's source files
    def filter!
      @files = SimpleCov.filtered(files)
    end
  end
end
