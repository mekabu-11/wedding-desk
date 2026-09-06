require "test_helper"
class ConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  setup do
    @owner = create_owner
    @doc = sample_document(create_wedding(@owner))
    analyze_sample(@doc)
    @candidate = @doc.candidates.first
  end
  teardown do
    @owner.destroy!
  end

  test "simultaneous approvals create one task" do
    gate = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          candidate = Candidate.find(@candidate.id)
          gate.pop
          ReviewCandidate.call(candidate, decision: "accept", attributes: acceptance_attributes(candidate))
        end
      end
    end
    2.times { gate << true }
    results = threads.map(&:value)
    assert_equal 1, @doc.wedding.tasks.count
    assert_equal results.first.id, results.last.id
  end

  test "simultaneous analysis starts result in a single active run" do
    gate = Queue.new
    results = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          begin
            Analysis::Start.call(Document.find(@doc.id))
            results << "started"
          rescue Analysis::Error => error
            results << error.code
          end
        end
      end
    end
    2.times { gate << true }
    threads.each(&:value)
    assert_equal ["already_processing", "started"], 2.times.map { results.pop }.sort
    assert_equal 1, @doc.analysis_runs.where(status: "pending").count
  end
end
