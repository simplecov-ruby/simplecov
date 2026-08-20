# frozen_string_literal: true

module SimpleCov
  module CLI
    module Watch
      # What one batch of changed files means for the next run, decided
      # over the same selection walk `simplecov affected` uses — the
      # watch loop knows exactly which files changed, so the recorded
      # map answers without a git diff.
      module TestPlan
      module_function

        # {run:, tests:} where nil tests mean the full command. A report
        # with no map, a malformed one, or any fail-open trigger runs
        # everything; an empty selection runs nothing.
        def build(changed, document, root:, input:, stderr:)
          contexts = document["contexts"]
          return {run: true, tests: nil} unless contexts.is_a?(Array) && contexts.all?(String)

          selection = Affected::Selection.build(changed, document, contexts, {input: input}, stderr, root: root)
          return {run: true, tests: nil} if selection.nil? || !selection[:triggers].empty?
          return {run: false, tests: []} if selection[:tests].empty?

          {run: true, tests: selection[:tests]}
        end

        # The watch set a report defines: its tracked files plus the
        # files of its recorded tests.
        def watched_paths(document, root)
          none = [] #: Array[String]
          coverage = document["coverage"]
          sources = coverage.is_a?(Hash) ? coverage.keys : none
          contexts = document["contexts"]
          tests = contexts.is_a?(Array) ? contexts.filter_map { |id| Affected::Selection.test_file_of(id.to_s) } : none
          (sources + tests.map { |path| File.expand_path(path, root) }).uniq
        end
      end
    end
  end
end
