# frozen_string_literal: true

module SimpleCov
  module TestContexts
    # Interns `[rerun_id, human_name]` entries to stable indices and,
    # unlike `Combine::IdentityInterner`, exposes the ordered table for
    # serialization. The rerun id is the identity; the first-seen name
    # wins.
    class TestTable
      attr_reader :entries

      def initialize
        @indices = {}
        @entries = []
      end

      def intern(id, name = id)
        @indices[id] ||= begin
          entry = [id, name].freeze #: entry
          @entries << entry
          @entries.size - 1
        end
      end
    end
  end
end
