# frozen_string_literal: true

module SimpleCov
  module CLI
    module Watch
      module TestPlan
        extend self

        # The `--global` patterns and the `global_files` ones, when there are none.
        def no_global
          none = [] #: Array[String]
          {global: none, global_files: none}
        end

        # {run:, tests:} where nil tests mean the full command. A report with no map,
        # a malformed one, or any fail-open trigger runs everything; an empty
        # selection runs nothing.
        def build(changed, document, root:, input:, stderr:, global: no_global)
          contexts = document["contexts"]
          return {run: true, tests: nil} unless contexts.instance_of?(Array) && contexts.all?(String)

          opts = {input: input, by_file: false, **global}
          selection = Affected::Selection.build(changed, document, contexts, opts, stderr, root: root)
          return {run: true, tests: nil} if selection.nil? || !selection.fetch(:triggers).empty?
          return {run: false, tests: []} if selection.fetch(:tests).empty?

          {run: true, tests: selection.fetch(:tests)}
        end

        # The watch set a report defines, its tracked files plus the files of its
        # recorded tests, and the files global patterns match, which a report
        # mostly leaves out.
        def watched_paths(document, root, global = no_global)
          none = [] #: Array[String]
          coverage = document["coverage"]
          sources = coverage.instance_of?(Hash) ? coverage.keys : none
          tests = recorded_test_files(document).map { |path| File.expand_path(path, root) }
          matched = Dir.glob(global.values.flatten, base: root).map { |path| File.expand_path(path, root) }
          (sources + tests + matched.select { |path| File.file?(path) }).uniq
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
