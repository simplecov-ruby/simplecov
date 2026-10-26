# frozen_string_literal: true

module SimpleCov
  module CLI
    module Affected
      module Selection
        extend self

        def build(changed, document, contexts, opts, stderr, root:)
          none = {} #: Hash[String, untyped]
          coverage = document.fetch("coverage", none)
          unless coverage.instance_of?(Hash)
            return CoverageFile.report_invalid(stderr, "affected", opts.fetch(:input), '"coverage" must be an object')
          end

          state = initial_state(changed, contexts, coverage, opts, stderr, root: root)
          return nil unless changed.all? { |path| classify(path, state) }

          {tests: state.fetch(:tests).uniq.sort, triggers: state.fetch(:triggers), reasons: reasons(state)}
        end

        # Selected test file => changed file => the recorded tests that tie them,
        # sorted throughout, ids in line order. A changed test file is its own
        # reason, through no recorded test. Each id is recorded once per changed
        # file, and every id under a test file names that file.
        def reasons(state)
          state.fetch(:reasons).sort.to_h do |file, by_change|
            [file, by_change.sort.to_h { |changed, ids| [changed, ids.sort_by { |id| line_order(id) }] }]
          end
        end

        # A bare file id, a test file's own loading, has no line and comes first.
        def line_order(id)
          id[/:(\d+)\z/, 1].to_i
        end

        def initial_state(changed, contexts, coverage, opts, stderr, root:)
          {
            tests: [], triggers: [], reasons: {}, changed: changed, contexts: contexts,
            known: contexts.each_with_object(Set.new) { |id, set| set << test_file_of(id) },
            index: CoverageFile.exact_index(coverage), root: root, opts: opts, stderr: stderr
          } #: Hash[Symbol, untyped]
        end

        # A file declared global runs everything. Otherwise a recorded test file
        # selects itself, a file the report covers selects the
        # files of the tests touching it, a test-looking file the map has never seen
        # always runs, and anything else is a trigger. Changed paths are exact
        # root-relative names, so they resolve against the report exactly: a
        # lookalike entry elsewhere must not stand in for a file it doesn't carry.
        GLOB = File::FNM_PATHNAME | File::FNM_EXTGLOB

        def classify(path, state)
          global = global_match(path, state.fetch(:opts))
          return state.fetch(:triggers) << "#{path} changed and matches #{global}" if global

          entry = entry_for(path, state)
          if state.fetch(:known).include?(path)
            select_test_file(path, state)
          elsif entry
            select_covering(path, entry, state)
          elsif TEST_FILE_NAME.match?(File.basename(path))
            select_test_file(path, state, note_deleted: false)
          else
            note_untracked(path, state)
          end
        end

        # The pattern a changed file matches, named by where it came from: a
        # `--global` flag or the `global_files` that `.simplecov` declares.
        def global_match(path, opts)
          flag = opts.fetch(:global).find { |pattern| File.fnmatch?(pattern, path, GLOB) }
          return "--global #{flag}" if flag

          configured = opts.fetch(:global_files).find { |pattern| File.fnmatch?(pattern, path, GLOB) }
          "global_files pattern #{configured}" if configured
        end

        def note_untracked(path, state)
          state.fetch(:triggers) << "#{path} changed but #{state.fetch(:opts).fetch(:input)} has no data for it"
        end

        # A changed test file runs, unless the change is its deletion: its tests are
        # gone, which removes them from the answer without distrusting the map.
        def select_test_file(path, state, note_deleted: true)
          if on_disk?(path, state)
            select(path, path, nil, state)
          elsif note_deleted
            state.fetch(:stderr).puts("simplecov affected: skipping deleted test file #{path}")
          end
          path
        end

        def select(file, changed, id, state)
          state.fetch(:tests) << file
          reasons = state.fetch(:reasons) #: Hash[String, Hash[String, Array[String]]]
          by_change = {} #: Hash[String, Array[String]]
          ids = [] #: Array[String]
          ids = (reasons[file] ||= by_change)[changed] ||= ids
          ids << id if id
        end

        # Existence judged at the repository root the paths are relative to, not the
        # cwd, so a subdirectory run answers the same.
        def on_disk?(path, state)
          File.exist?(File.expand_path(path, state.fetch(:root)))
        end

        def entry_for(path, state)
          state.fetch(:index)[File.expand_path(path, state.fetch(:root))] || state.fetch(:index)[path]
        end

        # Only the tests that ran the changed lines' methods, when the change can
        # be narrowed to methods, and every test touching the file otherwise. A
        # changed statement that ran only outside recorded tests, such as a
        # constant set as the file loads, falls back to the full suite, since
        # tests that never ran it can still read what it set.
        def select_covering(path, entry, state)
          table = covering_table(path, entry, state)
          return unless table

          mask, load_time = narrowed(path, entry, state)
          mask ||= -1
          claimed = table.select { |_index, bitmap| bitmap.anybits?(mask) }
          return select_unclaimed(path, entry, mask, table, state) if claimed.empty?

          claimed.each_key { |index| select_context(state.fetch(:contexts).fetch(index), path, state) }
          line = ran_outside_tests(entry, load_time, claimed.each_value.reduce(:|))
          return table unless line

          state.fetch(:triggers) << "#{path} changed at line #{line}, in code that ran only outside recorded tests"
        end

        # The first changed line whose statement ran only outside the claimed
        # tests. A statement whose first line coverage leaves uncounted counts
        # through the nearest counted line before it.
        def ran_outside_tests(entry, load_time, claimed)
          counts = entry["lines"]
          return unless load_time && counts.instance_of?(Array)

          load_time.filter_map { |statement, line|
            index = counts.first(statement).rindex(&:itself)
            line if index && first_ran(counts, (1 << index) & ~claimed)
          }.min
        end

        # Code that ran while no test was being recorded (loading before the
        # first test, suite-level setup) can shape every test, so when no test
        # claims what changed there is nothing to narrow the run to. Without line
        # counts there is no telling whether it ran at all.
        def select_unclaimed(path, entry, mask, table, state)
          lines = entry["lines"]
          return note_untracked(path, state) unless lines.instance_of?(Array)

          return table unless first_ran(lines, mask)

          state.fetch(:triggers) << "#{path} changed but ran only outside recorded tests"
        end

        def first_ran(counts, mask)
          counts.each_with_index.find { |count, index| count.instance_of?(Integer) && count.positive? && mask[index].equal?(1) }&.last
        end

        # `affected` compares against the merge base, and a file it cannot find
        # there is not narrowed. `watch` has no base and compares only against
        # the recording.
        def narrowed(path, entry, state)
          opts = state.fetch(:opts)
          recorded = entry["source"]
          return unless path.end_with?(".rb") && recorded.instance_of?(Array) && recorded.all?(String)

          root = state.fetch(:root)
          current = read(File.expand_path(path, root))
          return unless current

          if opts.key?(:merge_base)
            base = base_source(path, opts.fetch(:merge_base), root)
            return unless base
          end
          mask, load_time = Narrowing.changes(recorded.map { |line| "#{line}\n" }.join, base, current)
          [(mask unless opts.fetch(:by_file)), load_time]
        end

        def read(path)
          File.read(path)
        rescue SystemCallError
          nil
        end

        def base_source(path, merge_base, root)
          return unless merge_base

          stdout, _detail, success = Git.capture("-C", root, "show", "#{merge_base}:#{path}")
          stdout if success
        end

        def covering_table(path, entry, state)
          unless entry.instance_of?(Hash)
            return CoverageFile.report_invalid(state.fetch(:stderr), "affected", state.fetch(:opts).fetch(:input),
              "entry for #{path} must be an object")
          end

          raw = entry["contexts"] || {}
          table = raw.instance_of?(Hash) && Tests.decode_table(raw, state.fetch(:contexts).size)
          return table if table

          CoverageFile.report_invalid(state.fetch(:stderr), "affected", state.fetch(:opts).fetch(:input),
            "entry for #{path} carries a malformed \"contexts\" table")
        end

        # Selected via its file, or a staleness trigger when it has no file to
        # select: a locationless id, or a file that exists neither on disk nor in
        # the change.
        def select_context(id, path, state)
          file = test_file_of(id)
          if file.nil?
            state.fetch(:triggers) << "recorded test #{id} touches #{path} but has no file location"
          elsif on_disk?(file, state)
            select(file, path, id, state)
          elsif !state.fetch(:changed).include?(file)
            state.fetch(:triggers) << "recorded test file #{file} no longer exists"
          end
        end

        # "spec/a_spec.rb:12", "spec/a_spec.rb[1:2:1]", and the :file
        # granularity's bare "spec/a_spec.rb" all name a file, while a
        # locationless fallback id names none.
        def test_file_of(id)
          base = id.sub(TEST_ID_TAIL, "")
          base if base.include?("/") || base.end_with?(".rb")
        end
      end
    end
  end
end
