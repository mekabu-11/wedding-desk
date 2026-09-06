module Analysis
  class Start
    def self.call(document)
      run = nil
      document.with_lock do
        raise Error.new("already_processing") unless document.retryable?
        # A stale job may finish later: the job checks the latest run before saving.
        document.analysis_runs.where(status: %w[pending processing]).update_all(status: "failed", error_code: "superseded")
        run = document.analysis_runs.create!(provider: document.sample? ? "sample" : "openai",
          model_version: document.sample? ? "fixture-v1" : ENV["LLM_MODEL"])
      end
      job = AnalyzeDocumentJob.perform_later(run.id)
      unless job
        run.update!(status: "failed", error_code: "enqueue_failed")
        raise Error.new("enqueue_failed")
      end
      run
    rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
      run&.update!(status: "failed", error_code: "enqueue_failed")
      raise Error.new("enqueue_failed")
    end
  end
end
