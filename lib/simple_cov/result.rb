require 'digest/sha1'
require 'yaml'

module SimpleCov
  class Result    
    attr_reader :original_result, :files
    attr_writer :created_at, :command_name
    alias_method :source_files, :files

    def initialize(original_result)
      @original_result = original_result.freeze
      @files = original_result.map {|filename, coverage| SimpleCov::SourceFile.new(filename, coverage)}.sort_by(&:filename)
      filter!
    end
  
    def filenames
      files.map(&:filename)
    end
    
    def groups
      @groups ||= SimpleCov.grouped(files)
    end
    
    def covered_percent
      files.map(&:covered_percent).inject(:+) / files.count.to_f
    end
    
    def format!
      SimpleCov.formatter.new.format(self)
    end
    
    # Defines when this result has been created
    def created_at
      @created_at ||= Time.now
    end
    
    # Stores the command name for this result (based upon command line args)
    # (currently only a plain SHA1)
    def command_name
      Digest::SHA1.hexdigest("#{$0} #{ARGV.join(" ")}")
    end
    
    # Returns a yaml dump of this result, which then can be reloaded using SimpleCov::Result.from_yaml
    def to_yaml
      {command_name => {:original_result => original_result, :created_at => created_at}}.to_yaml
    end
    
    # Loads a SimpleCov::Result#to_yaml dump
    def self.from_yaml(yaml)
      require 'pp'
      command_name, data = YAML.load(yaml).first
      result = SimpleCov::Result.new(data[:original_result])
      result.command_name = command_name
      result.created_at = data[:created_at]
      result
    end
    
    private
  
    def filter!
      @files = SimpleCov.filtered(files)
    end
  end
end