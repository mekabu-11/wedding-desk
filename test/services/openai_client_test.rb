require "test_helper"
class OpenaiClientTest < ActiveSupport::TestCase
  def stub_output(output, status: "completed")
    stub_request(:post, "https://api.openai.com/v1/responses").to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(status: status, output: [{ type: "message", content: [{ type: "output_text", text: JSON.generate(output) }] }]))
  end

  test "Responses request uses strict schema, no storage, no tools, and preserves data" do
    doc = sample_document
    with_api_env do
      stub = stub_output(Analysis::Sample.new.call(doc))
      data = Analysis::OpenaiClient.new.call(doc)
      assert_equal 2, data["tasks"].size
      assert_requested(:post, "https://api.openai.com/v1/responses") do |request|
        body = JSON.parse(request.body)
        body["store"] == false && body.dig("text", "format", "strict") == true && !body.key?("tools") && JSON.parse(body["input"])["text"] == doc.original_text
      end
    end
  end

  test "refusal, truncated output and HTTP error do not become successful empty results" do
    doc = sample_document
    with_api_env do
      stub_output({}, status: "incomplete")
      assert_equal "incomplete_output", assert_raises(Analysis::Error) { Analysis::OpenaiClient.new.call(doc) }.code
      stub_request(:post, "https://api.openai.com/v1/responses").to_return(status: 200, body: JSON.generate(status: "completed", output: [{ type: "message", content: [{ type: "refusal", refusal: "private provider detail" }] }]))
      assert_equal "refused", assert_raises(Analysis::Error) { Analysis::OpenaiClient.new.call(doc) }.code
      stub_request(:post, "https://api.openai.com/v1/responses").to_return(status: 401, body: "sensitive error body")
      error = assert_raises(Analysis::Error) { Analysis::OpenaiClient.new.call(doc) }
      assert_equal "provider_rejected", error.message
      refute_includes error.message, "sensitive"
    end
  end

  test "transient provider failure retries at most three times and retains document" do
    doc = sample_document
    doc.update!(sample: false)
    run = doc.analysis_runs.create!(provider: "openai")
    with_api_env do
      stub_request(:post, "https://api.openai.com/v1/responses").to_return(status: 503, body: "no")
      3.times { AnalyzeDocumentJob.perform_now(run.id) }
      assert_equal "failed", run.reload.status
      assert_equal 3, run.attempt
      assert_equal 2, enqueued_jobs.count { |job| job[:job] == AnalyzeDocumentJob }
      assert_equal 0, doc.candidates.count
      assert doc.reload.original_text.present?
    end
  end

  test "invalid evidence leaves no partially saved candidates" do
    doc = sample_document
    doc.update!(sample: false)
    run = doc.analysis_runs.create!(provider: "openai")
    data = Analysis::Sample.new.call(sample_document(create_wedding))
    data["tasks"][1]["quote"] = "fabricated"
    with_api_env do
      stub_output(data)
      AnalyzeDocumentJob.perform_now(run.id)
    end
    assert_equal "failed", run.reload.status
    assert_equal "invalid_evidence", run.error_code
    assert_equal 0, doc.candidates.count
  end

  test "valid response with no tasks is a successful result" do
    doc = sample_document
    doc.update!(sample: false)
    run = doc.analysis_runs.create!(provider: "openai")
    with_api_env do
      stub_output({ "summary" => "新しい依頼はありません。", "category" => "other", "tasks" => [] })
      AnalyzeDocumentJob.perform_now(run.id)
    end
    assert_equal "completed", run.reload.status
    assert_equal 0, doc.candidates.count
  end
  test "missing key fails explicitly without fabricating an analysis" do
    doc = sample_document
    doc.update!(sample: false)
    run = doc.analysis_runs.create!(provider: "openai")
    with_api_env do
      ENV.delete("OPENAI_API_KEY")
      AnalyzeDocumentJob.perform_now(run.id)
    end
    assert_equal "failed", run.reload.status
    assert_equal "not_configured", run.error_code
    assert_empty doc.candidates
    assert doc.reload.original_text.present?
    assert_not_requested :post, "https://api.openai.com/v1/responses"
  end

end
