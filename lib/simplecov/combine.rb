# frozen_string_literal: true

module SimpleCov
  # Namespace for the pieces that combine coverage results.
  #
  # `CoverageAccumulator` is the entry point: it folds any number of
  # resultsets together, delegating one file's lines, branches and methods to
  # the combiner modules alongside it.
  #
  module Combine
  end
end
