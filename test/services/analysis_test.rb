require "test_helper"
class AnalysisTest < ActiveSupport::TestCase
  test "sample creates candidates only, with verifiable evidence and encrypted storage" do
    doc = sample_document
    run = analyze_sample(doc)
    assert_equal "completed", run.status
    assert_equal 2, doc.candidates.count
    assert_equal 0, Task.count
    doc.candidates.each do |candidate|
      assert_includes doc.original_text, candidate.evidence["quote"]
      assert_equal "pending", candidate.review_status
    end
    raw = ActiveRecord::Base.connection.select_value("SELECT original_text FROM documents WHERE id = #{doc.id}")
    refute_includes raw, "BGM"
    raw_candidate = ActiveRecord::Base.connection.select_value("SELECT payload FROM candidates WHERE id = #{doc.candidates.first.id}")
    refute_includes raw_candidate, "BGM"
  end

  test "job replay and reanalysis never duplicate accepted or rejected candidates" do
    doc = sample_document
    first_run = analyze_sample(doc)
    accepted, rejected = doc.candidates.order(:id)
    task = ReviewCandidate.call(accepted, decision: "accept", attributes: acceptance_attributes(accepted))
    task.update!(title: "自分で直したタイトル", status: "done")
    ReviewCandidate.call(rejected, decision: "reject")
    AnalyzeDocumentJob.perform_now(first_run.id)
    analyze_sample(doc)
    assert_equal 2, doc.candidates.count
    assert_equal 1, doc.wedding.tasks.count
    assert_equal "自分で直したタイトル", task.reload.title
    assert_equal "done", task.status
    assert_equal "rejected", rejected.reload.review_status
  end

  test "duplicate acceptance is idempotent and rejected candidates stay rejected" do
    doc = sample_document
    analyze_sample(doc)
    candidate = doc.candidates.first
    2.times { ReviewCandidate.call(candidate, decision: "accept", attributes: acceptance_attributes(candidate)) }
    assert_equal 1, doc.wedding.tasks.count
    other = doc.candidates.last
    ReviewCandidate.call(other, decision: "reject")
    ReviewCandidate.call(other, decision: "accept", attributes: acceptance_attributes(other))
    assert_nil other.reload.task
  end

  test "invalid manual date never silently becomes no deadline" do
    doc = sample_document
    analyze_sample(doc)
    candidate = doc.candidates.first
    attrs = acceptance_attributes(candidate).merge("due_on" => "2026-02-30")
    assert_raises(ActiveRecord::RecordInvalid) { ReviewCandidate.call(candidate, decision: "accept", attributes: attrs) }
    assert_equal "pending", candidate.reload.review_status
    assert_equal 0, Task.count
  end

  test "fabricated evidence and impossible dates are rejected" do
    doc = sample_document
    data = Analysis::Sample.new.call(doc)
    data["tasks"][0]["quote"] = "原文にない文章"
    assert_equal "invalid_evidence", assert_raises(Analysis::Error) { Analysis::Validator.call(data, doc) }.code
    data = Analysis::Sample.new.call(doc)
    data["tasks"][0]["due_on"] = "2026-02-30"
    assert_equal "invalid_date", assert_raises(Analysis::Error) { Analysis::Validator.call(data, doc) }.code
  end

  test "missing fields and unexpected keys fail schema validation" do
    doc = sample_document
    data = Analysis::Sample.new.call(doc)
    data["tasks"][0].delete("assignee")
    assert_raises(Analysis::Error) { Analysis::Validator.call(data, doc) }
    data = Analysis::Sample.new.call(doc).merge("secret_action" => "send")
    assert_raises(Analysis::Error) { Analysis::Validator.call(data, doc) }
  end

  test "unknown assignee and absent deadline remain unknown" do
    doc = sample_document
    data = Analysis::Sample.new.call(doc)
    data["tasks"][0].merge!("assignee" => "unknown", "due_on" => nil, "due_at" => nil, "original_due_text" => nil)
    result = Analysis::Validator.call(data, doc)
    assert_nil result["tasks"][0]["due_on"]
    assert_equal "unknown", result["tasks"][0]["assignee"]
  end

  test "same normalized original is duplicate within a wedding only" do
    doc = sample_document
    duplicate = doc.wedding.documents.new(original_text: "  #{doc.original_text}  ", source_type: "line")
    refute duplicate.valid?
    assert duplicate.errors.of_kind?(:content_hash, :taken)
    assert sample_document(create_wedding).persisted?
  end

  test "latest run supersedes an older queued run" do
    doc = sample_document
    old = doc.analysis_runs.create!(provider: "sample")
    latest = doc.analysis_runs.create!(provider: "sample")
    AnalyzeDocumentJob.perform_now(old.id)
    assert_equal 0, doc.candidates.count
    AnalyzeDocumentJob.perform_now(latest.id)
    assert_equal 2, doc.candidates.count
  end

  test "job on deleted document does not revive source or tasks" do
    doc = sample_document
    run = analyze_sample(doc)
    candidate = doc.candidates.first
    ReviewCandidate.call(candidate, decision: "accept", attributes: acceptance_attributes(candidate))
    id = run.id
    doc.destroy!
    AnalyzeDocumentJob.perform_now(id)
    assert_equal 0, Document.count
    assert_equal 0, Task.count
    assert_equal 0, Candidate.count
  end

  test "concurrent task edits are not overwritten" do
    doc = sample_document
    analyze_sample(doc)
    candidate = doc.candidates.first
    task = ReviewCandidate.call(candidate, decision: "accept", attributes: acceptance_attributes(candidate))
    stale = Task.find(task.id)
    task.update!(title: "最新の修正")
    assert_raises(ActiveRecord::StaleObjectError) { stale.update!(title: "古い画面の修正") }
  end
  test "impossible calendar date in a timestamp is rejected" do
    doc = sample_document
    data = Analysis::Sample.new.call(doc)
    data["tasks"][0].merge!("due_on" => nil, "due_at" => "2026-02-30T12:00:00+09:00")
    assert_equal "invalid_date", assert_raises(Analysis::Error) { Analysis::Validator.call(data, doc) }.code
    analyze_sample(doc)
    candidate = doc.candidates.first
    assert_raises(ActiveRecord::RecordInvalid) do
      ReviewCandidate.call(candidate, decision: "accept", attributes: acceptance_attributes(candidate).merge("due_on" => nil, "due_at" => "2026-02-30T12:00"))
    end
  end

  test "date-only deadline is not overdue during its day in Tokyo" do
    doc = sample_document
    analyze_sample(doc)
    candidate = doc.candidates.first
    task = ReviewCandidate.call(candidate, decision: "accept", attributes: acceptance_attributes(candidate))
    travel_to Time.zone.local(2026, 9, 20, 23, 59) do
      refute task.overdue?
    end
    travel_to Time.zone.local(2026, 9, 21, 0, 0) do
      assert task.overdue?
    end
  end

  test "stale run can be restarted but a current one cannot" do
    doc = sample_document
    run = doc.analysis_runs.create!(provider: "sample", status: "processing")
    assert_raises(Analysis::Error) { Analysis::Start.call(doc) }
    run.update_columns(updated_at: 6.minutes.ago)
    latest = Analysis::Start.call(doc)
    assert_equal "failed", run.reload.status
    assert_equal "pending", latest.status
  end

end
