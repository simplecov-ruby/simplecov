# frozen_string_literal: true

require "open3"

# Splits the subjects mutant selects for a diff across CI runners.
#
# Mutant matches each subject's line range against the diff, so a comment
# removed above a method marks every method below it as touched: a formatting
# pass over the tree selects most of the library. Sharding is what keeps that
# case inside a job timeout instead of running for hours on one runner.
module MutantShard
  extend self

  def subjects_since(ref)
    output, status = Open3.capture2("bundle", "exec", "mutant", "environment", "subject", "list", "--since", ref)
    raise "mutant could not list the subjects touched since #{ref}" unless status.success?

    # A subject name never contains a space, which is what tells it apart from
    # the "Subjects in environment: N" line mutant ends the listing with.
    output.lines.map(&:chomp).select { |line| line.start_with?("SimpleCov") && !line.include?(" ") }
  end

  # Round robin rather than contiguous slices. Mutant lists subjects sorted, so
  # a namespace lands together and the expensive ones cluster: every
  # `SimpleCov::CLI::Diff` subject shells out, and contiguous slicing would put
  # them all in one shard, which is the shard that times out. Taking every
  # TOTAL-th subject spreads a slow namespace across every runner instead.
  def shard(subjects, index, total)
    subjects.select.with_index { |_subject, position| position % total == index }
  end
end
