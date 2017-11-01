# frozen_string_literal: true

require "helper"

if SimpleCov.usable?
  describe SimpleCov do
    describe ".result" do
      before do
        SimpleCov.clear_result
        allow(Coverage).to receive(:result).once.and_return({})
      end

      context "with merging disabled" do
        before do
          allow(SimpleCov).to receive(:use_merging).once.and_return(false)
        end

        context "when not running" do
          before do
            allow(SimpleCov).to receive(:running).and_return(false)
          end

          it "returns nil" do
            expect(SimpleCov.result).to be_nil
          end
        end

        context "when running" do
          before do
            allow(SimpleCov).to receive(:running).and_return(true, false)
          end

          it "uses the result from Coverage" do
            expect(Coverage).to receive(:result).once.and_return(__FILE__ => [0, 1])
            expect(SimpleCov.result.filenames).to eq [__FILE__]
          end

          it "adds not-loaded-files" do
            expect(SimpleCov).to receive(:add_not_loaded_files).once.and_return({})
            SimpleCov.result
          end

          it "doesn't store the current coverage" do
            expect(SimpleCov::ResultMerger).not_to receive(:store_result)
            SimpleCov.result
          end

          it "doesn't merge the result" do
            expect(SimpleCov::ResultMerger).not_to receive(:merged_result)
            SimpleCov.result
          end

          it "caches its result" do
            result = SimpleCov.result
            expect(SimpleCov.result).to be(result)
          end
        end
      end

      context "with merging enabled" do
        let(:the_merged_result) { double }

        before do
          allow(SimpleCov).to receive(:use_merging).once.and_return(true)
          allow(SimpleCov::ResultMerger).to receive(:store_result).once
          allow(SimpleCov::ResultMerger).to receive(:merged_result).once.and_return(the_merged_result)
        end

        context "when not running" do
          before do
            allow(SimpleCov).to receive(:running).and_return(false)
          end

          it "merges the result" do
            expect(SimpleCov.result).to be(the_merged_result)
          end
        end

        context "when running" do
          before do
            allow(SimpleCov).to receive(:running).and_return(true, false)
          end

          it "uses the result from Coverage" do
            expect(Coverage).to receive(:result).once.and_return({})
            SimpleCov.result
          end

          it "adds not-loaded-files" do
            expect(SimpleCov).to receive(:add_not_loaded_files).once.and_return({})
            SimpleCov.result
          end

          it "stores the current coverage" do
            expect(SimpleCov::ResultMerger).to receive(:store_result).once
            SimpleCov.result
          end

          it "merges the result" do
            expect(SimpleCov.result).to be(the_merged_result)
          end

          it "caches its result" do
            result = SimpleCov.result
            expect(SimpleCov.result).to be(result)
          end
        end
      end
    end

    describe ".set_exit_exception" do
      context "when an exception has occurred" do
        let(:error) { StandardError.new "SomeError" }

        after do
          # Clear the exit_exception
          SimpleCov.set_exit_exception
        end

        it "captures the current exception" do
          begin
            raise error
          rescue
            SimpleCov.set_exit_exception
            expect(SimpleCov.exit_exception).to be(error)
          end
        end
      end

      context "when an exception has not occurred" do
        it "has no exit_exception" do
          SimpleCov.set_exit_exception
          expect(SimpleCov.exit_exception).to eq(nil)
        end
      end
    end

    describe ".exit_status_from_exception" do
      context "when no exception has occurred" do
        before do
          allow(SimpleCov).to receive(:exit_exception).and_return(nil)
        end

        it "returns SimpleCov::ExitCodes::SUCCESS" do
          expect(SimpleCov.exit_status_from_exception).to eq(SimpleCov::ExitCodes::SUCCESS)
        end
      end

      context "when a SystemExit has occurred" do
        let(:system_exit) { SystemExit.new(1) }

        before do
          allow(SimpleCov).to receive(:exit_exception).and_return(system_exit)
        end

        it "returns the SystemExit status" do
          expect(SimpleCov.exit_status_from_exception).to eq(system_exit.status)
        end
      end

      context "when a non SystemExit occurrs" do
        let(:error) { StandardError.new "NonSystemExit" }

        before do
          allow(SimpleCov).to receive(:exit_exception).and_return(error)
        end

        it "return SimpleCov::ExitCodes::EXCEPTION" do
          expect(SimpleCov.exit_status_from_exception).to eq(SimpleCov::ExitCodes::EXCEPTION)
        end
      end
    end
  end
end
