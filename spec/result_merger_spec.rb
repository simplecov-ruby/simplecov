require "helper"
require "tempfile"
require "timeout"

if SimpleCov.usable?
  describe SimpleCov::ResultMerger do
    before do
      SimpleCov::ResultMerger.clear_resultset
      File.delete(SimpleCov::ResultMerger.resultset_path) if File.exist?(SimpleCov::ResultMerger.resultset_path)
    end

    describe "with two faked coverage resultsets" do
      before do
        @resultset1 = {
          source_fixture("sample.rb") => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
          source_fixture("app/models/user.rb") => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
          source_fixture("app/controllers/sample_controller.rb") => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
          source_fixture("resultset1.rb") => [1, 1, 1, 1],
          source_fixture("parallel_tests.rb") => [nil, 0, nil, 0],
          source_fixture("conditionally_loaded_1.rb") => [nil, 0, 1],  # loaded only in the first resultset
        }

        @resultset2 = {
          source_fixture("sample.rb") => [1, nil, 1, 1, nil, nil, 1, 1, nil, nil],
          source_fixture("app/models/user.rb") => [nil, 1, 5, 1, nil, nil, 1, 0, nil, nil],
          source_fixture("app/controllers/sample_controller.rb") => [nil, 3, 1, nil, nil, nil, 1, 0, nil, nil],
          source_fixture("resultset2.rb") => [nil, 1, 1, nil],
          source_fixture("parallel_tests.rb") => [nil, nil, 0, 0],
          source_fixture("conditionally_loaded_2.rb") => [nil, 0, 1],  # loaded only in the second resultset
        }
      end

      # See Github issue #6
      it "returns an empty hash when the resultset cache file is empty" do
        File.open(SimpleCov::ResultMerger.resultset_path, "w+") { |f| f.puts "" }
        expect(SimpleCov::ResultMerger.resultset).to be_empty
      end

      # See Github issue #6
      it "returns an empty hash when the resultset cache file is not present" do
        system "rm #{SimpleCov::ResultMerger.resultset_path}" if File.exist?(SimpleCov::ResultMerger.resultset_path)
        expect(SimpleCov::ResultMerger.resultset).to be_empty
      end

      context "and results generated from those" do
        before do
          system "rm #{SimpleCov::ResultMerger.resultset_path}" if File.exist?(SimpleCov::ResultMerger.resultset_path)
          @result1 = SimpleCov::Result.new(@resultset1)
          @result1.command_name = "result1"
          @result2 = SimpleCov::Result.new(@resultset2)
          @result2.command_name = "result2"
        end

        context "with stored results" do
          before do
            SimpleCov::ResultMerger.store_result(@result1)
            SimpleCov::ResultMerger.store_result(@result2)
          end

          it "has stored data in resultset_path JSON file" do
            expect(File.readlines(SimpleCov::ResultMerger.resultset_path).length).to be > 50
          end

          it "returns a hash containing keys ['result1' and 'result2'] for resultset" do
            expect(SimpleCov::ResultMerger.resultset.keys.sort).to eq %w[result1 result2]
          end

          it "returns proper values for merged_result" do
            expect(SimpleCov::ResultMerger.merged_result.source_files.find { |s| s.filename =~ /user/ }.lines.map(&:coverage)).to eq([nil, 2, 6, 2, nil, nil, 2, 0, nil, nil])
          end

          context "with second result way above the merge_timeout" do
            before do
              @result2.created_at = Time.now - 172_800 # two days ago
              SimpleCov::ResultMerger.store_result(@result2)
            end

            it "has only one result in SimpleCov::ResultMerger.results" do
              expect(SimpleCov::ResultMerger.results.length).to eq(1)
            end
          end
        end
      end
    end

    describe ".store_result" do
      it "refreshes the resultset" do
        set = SimpleCov::ResultMerger.resultset
        SimpleCov::ResultMerger.store_result({})
        new_set = SimpleCov::ResultMerger.resultset
        expect(new_set).not_to be(set)
      end

      it "persists to disk" do
        SimpleCov::ResultMerger.store_result("a" => [1])
        SimpleCov::ResultMerger.clear_resultset
        new_set = SimpleCov::ResultMerger.resultset
        expect(new_set).to eq("a" => [1])
      end

      it "synchronizes writes" do
        expect(SimpleCov::ResultMerger).to receive(:synchronize_resultset)
        SimpleCov::ResultMerger.store_result({})
      end
    end

    describe ".resultset" do
      it "caches" do
        set = SimpleCov::ResultMerger.resultset
        new_set = SimpleCov::ResultMerger.resultset
        expect(new_set).to be(set)
      end

      it "synchronizes reads" do
        expect(SimpleCov::ResultMerger).to receive(:synchronize_resultset)
        SimpleCov::ResultMerger.resultset
      end
    end

    describe ".synchronize_resultset" do
      it "is reentrant (i.e. doesn't block its own process)" do
        # without @resultset_locked, this spec would fail and
        # `.store_result` wouldn't work
        expect do
          Timeout.timeout(1) do
            SimpleCov::ResultMerger.synchronize_resultset do
              SimpleCov::ResultMerger.synchronize_resultset do
              end
            end
          end
        end.not_to raise_error
      end

      it "blocks other processes" do
        file = Tempfile.new("foo")

        other_process = open("|ruby -e " + Shellwords.escape(<<-CODE) + " 2>/dev/null")
          require "simplecov"
          SimpleCov.coverage_dir(#{SimpleCov.coverage_dir.inspect})

          # ensure the parent process has enough time to get a
          # lock before we do
          sleep 0.5

          $stdout.sync = true
          puts "running" # see `sleep`s in parent process

          SimpleCov::ResultMerger.synchronize_resultset do
            File.open(#{file.path.inspect}, "a") { |f| f.write("process 2\n") }
          end
        CODE

        SimpleCov::ResultMerger.synchronize_resultset do
          # wait until the child process is going, and then wait some more
          # so we can be sure it blocks on the lock we already have.
          sleep 0.1 until other_process.gets == "running\n"
          sleep 1

          # despite the sleeps, this will be written first since we got
          # the first lock
          File.open(file.path, "a") { |f| f.write("process 1\n") }
        end

        # wait for it to finish
        other_process.gets

        expect(file.read).to eq("process 1\nprocess 2\n")
      end
    end
  end
end
