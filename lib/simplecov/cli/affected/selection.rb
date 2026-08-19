# frozen_string_literal: true

module SimpleCov
  module CLI
    module Affected
      # The selection walk: every changed file's contribution to the
      # answer, accumulated as selected test files plus the triggers
      # that mean the map cannot be trusted for this change.
      module Selection
        # What a test file is named like, for changed files the map has
        # never seen: RSpec's *_spec.rb and Minitest's *_test.rb and
        # test_*.rb conventions.
        TEST_FILE_NAME = /\A(?:test_.*|.*_(?:test|spec))\.rb\z/

      module_function

        # Walk every changed file into a selection ({tests:, triggers:}),
        # nil after reporting malformed input. A non-empty triggers list
        # means the answer is the full suite. `root` is the repository
        # toplevel the changed paths are relative to.
        def build(changed, document, contexts, opts, stderr, root:)
          none = {} #: Hash[String, untyped]
          coverage = document.fetch("coverage", none)
          unless coverage.is_a?(Hash)
            return CoverageFile.report_invalid(stderr, "affected", opts[:input], '"coverage" must be an object')
          end

          state = initial_state(changed, contexts, coverage, opts, stderr, root: root)
          return nil unless changed.all? { |path| classify(path, state) }

          {tests: state[:tests].uniq.sort, triggers: state[:triggers]}
        end

        def initial_state(changed, contexts, coverage, opts, stderr, root:)
          {
            tests: [], triggers: [], changed: changed, contexts: contexts,
            known: contexts.filter_map { |id| test_file_of(id) }.uniq,
            index: CoverageFile.exact_index(coverage), root: root, opts: opts, stderr: stderr
          } #: Hash[Symbol, untyped]
        end

        # One changed file's contribution: a recorded test file selects
        # itself, a file the report covers selects the files of the tests
        # touching it, a test-looking file the map has never seen always
        # runs, and anything else is outside the tracked set — a trigger.
        # Changed paths are exact root-relative names, so they resolve
        # against the report exactly — a lookalike entry elsewhere in the
        # report must not stand in for a file the report doesn't carry.
        def classify(path, state)
          return select_test_file(path, state) if state[:known].include?(path)

          entry = entry_for(path, state)
          return select_covering(path, entry, state) if entry
          return select_test_file(path, state, note_deleted: false) if TEST_FILE_NAME.match?(File.basename(path))

          state[:triggers] << "#{path} changed but #{state[:opts][:input]} has no data for it"
          true
        end

        # A changed test file runs, unless the change is its deletion —
        # its tests are gone, which removes them from the answer without
        # distrusting the map. Returns the path, a truthy "classified".
        def select_test_file(path, state, note_deleted: true)
          if on_disk?(path, state)
            state[:tests] << path
          elsif note_deleted
            state[:stderr].puts("simplecov affected: skipping deleted test file #{path}")
          end
          path
        end

        # Existence judged at the repository root the paths are relative
        # to, not the cwd, so a subdirectory run answers the same.
        def on_disk?(path, state)
          File.exist?(File.expand_path(path, state[:root]))
        end

        # The report entry behind one changed path — resolved against the
        # git root, or literal for a relative-keyed document.
        def entry_for(path, state)
          state[:index][File.expand_path(path, state[:root])] || state[:index][path]
        end

        def select_covering(path, entry, state)
          table = covering_table(path, entry, state)
          return nil unless table

          table.each_key { |index| select_context(state[:contexts].fetch(index), path, state) }
          path
        end

        # The entry's decoded context table, nil after reporting a
        # malformed one — which poisons the whole answer, the same
        # all-or-nothing tolerance `simplecov tests` applies.
        def covering_table(path, entry, state)
          unless entry.is_a?(Hash)
            return CoverageFile.report_invalid(state[:stderr], "affected", state[:opts][:input],
                                               "entry for #{path} must be an object")
          end

          raw = entry["contexts"] || {}
          table = raw.is_a?(Hash) && Tests.decode_table(raw, state[:contexts].size)
          return table if table

          CoverageFile.report_invalid(state[:stderr], "affected", state[:opts][:input],
                                      "entry for #{path} carries a malformed \"contexts\" table")
        end

        # One recorded test touching a changed file: selected via its
        # file, or a staleness trigger when it has no file to select — a
        # locationless id, or a file that exists neither on disk nor in
        # the change (whose own classification already noted the
        # deletion).
        def select_context(id, path, state)
          file = test_file_of(id)
          if file.nil?
            state[:triggers] << "recorded test #{id} touches #{path} but has no file location"
          elsif on_disk?(file, state)
            state[:tests] << file
          elsif !state[:changed].include?(file)
            state[:triggers] << "recorded test file #{file} no longer exists"
          end
        end

        # The file behind a recorded test id: "spec/a_spec.rb:12" and the
        # :file granularity's bare "spec/a_spec.rb" both name one, while a
        # locationless fallback id ("FooTest#test_bar") names none.
        def test_file_of(id)
          base = id.sub(/:\d+\z/, "")
          base if base.include?("/") || base.end_with?(".rb")
        end
      end
    end
  end
end
