# frozen_string_literal: true

module SimpleCov
  #
  # Responsible for producing file coverage metrics.
  #
  class RunFileCoverage
    def self.start(*args)
      new(*args).call
    end

    def initialize(absolute_path)
      @lines             = File.foreach(absolute_path)
      @absolute_path     = absolute_path
      @classified_result = {}
    end

    #
    # Simulate normal file coverage report on
    # ruby 2.5 and return similar hash with lines and branches keys
    #
    # @return [Hash]
    #
    def call
      @classified_result[:lines]    = LinesClassifier.new.classify(lines)
      @classified_result[:branches] = BranchesPerFile.start(absolute_path)
      @classified_result
    end

  private

    # rubocop:disable TrivialAccessors
    # attr_reader under private for ruby < 2.3.7 raise "warning: private attribute?"
    def lines
      @lines
    end

    def absolute_path
      @absolute_path
    end
    # rubocop:enable TrivialAccessors
  end
end
