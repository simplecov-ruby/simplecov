# frozen_string_literal: true

module SimpleCov
  module CLI
    module Watch
      module TestPlan
        extend self

        # {run:, tests:} where nil tests mean the full command. A report with no map,
        # a malformed one, or any fail-open trigger runs everything; an empty
        # selection runs nothing.
        def build(changed, document, root:, input:, stderr:)
          contexts = document["contexts"]
          return {run: true, tests: nil} unless contexts.instance_of?(Array) && contexts.all?(String)

          selection = Affected::Selection.build(changed, document, contexts, {input: input}, stderr, root: root)
          return {run: true, tests: nil} if selection.nil? || !selection.fetch(:triggers).empty?
          return {run: false, tests: []} if selection.fetch(:tests).empty?

          {run: true, tests: selection.fetch(:tests)}
        end

        # The watch set a report defines: its tracked files plus the files of its
        # recorded tests.
        def watched_paths(document, root)
          none = [] #: Array[String]
          coverage = document["coverage"]
          sources = coverage.instance_of?(Hash) ? coverage.keys : none
          tests = recorded_test_files(document).map { |path| File.expand_path(path, root) }
          (sources + tests).uniq
        end

        def recorded_test_files(document)
          none = [] #: Array[String]
          contexts = document["contexts"]
          return none unless contexts.instance_of?(Array)

          contexts.filter_map { |id| Affected::Selection.test_file_of(id.to_s) }
        end
      end
    end
  end
end
