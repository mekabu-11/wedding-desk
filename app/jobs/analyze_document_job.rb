class AnalyzeDocumentJob < ApplicationJob
  queue_as :default
  def perform(run_id)
    run = AnalysisRun.find_by(id: run_id)
    return unless run
    document = run.document
    token = SecureRandom.uuid
    claimed = false
    document.with_lock do
      run.reload
      if document.latest_run.id == run.id && (run.status == "pending" || (run.status == "processing" && run.updated_at < 3.minutes.ago))
        run.update!(status: "processing", started_at: Time.current, attempt_token: token, attempt: run.attempt + 1)
        claimed = true
      end
    end
    return unless claimed
    provider = run.provider == "sample" ? Analysis::Sample.new : Analysis::OpenaiClient.new
    result = Analysis::Validator.call(provider.call(document), document)
    document.with_lock do
      run.reload
      return unless document.latest_run.id == run.id && run.attempt_token == token && run.status == "processing"
      result.fetch("tasks").each do |item|
        quote = item.fetch("quote")
        payload = item.except("quote")
        fingerprint = Digest::SHA256.hexdigest(JSON.generate(payload.except("uncertainty_reasons").sort.to_h) + quote)
        next if document.candidates.exists?(fingerprint: fingerprint)
        document.candidates.create!(analysis_run: run, payload: payload,
          evidence: { "quote" => quote, "offset" => document.original_text.index(quote), "length" => quote.length }, fingerprint: fingerprint)
      end
      run.update!(status: "completed", summary: result.fetch("summary"), category: result.fetch("category"), finished_at: Time.current, error_code: nil)
    end
  rescue ActiveRecord::RecordNotFound
    # Deletion during analysis is intentional; never recreate the document.
    nil
  rescue Analysis::Error => error
    handle_failure(run_id, token, error.code)
  rescue StandardError => error
    # Do not log exception messages: providers/validators may include original text.
    Rails.logger.error("analysis_failed run_id=#{run_id} error_class=#{error.class.name}")
    handle_failure(run_id, token, "unexpected_error")
  end

  private
  def handle_failure(run_id, token, code)
    run = AnalysisRun.find_by(id: run_id)
    return unless run
    retry_job_later = false
    run.document.with_lock do
      run.reload
      return unless run.attempt_token == token && run.status == "processing"
      retry_job_later = %w[provider_unavailable rate_limited].include?(code) && run.attempt < 3
      run.update!(status: retry_job_later ? "pending" : "failed", error_code: code, finished_at: retry_job_later ? nil : Time.current)
    end
    self.class.set(wait: 30.seconds).perform_later(run_id) if retry_job_later
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
