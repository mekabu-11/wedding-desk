ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
WebMock.disable_net_connect!(allow_localhost: true)

class ActiveSupport::TestCase
  include ActiveJob::TestHelper
  def create_owner
    User.create!(email: "owner-#{SecureRandom.hex(5)}@example.test", password: "test-password-12345")
  end
  def create_wedding(user = create_owner)
    user.create_wedding!(name: "テストの結婚式", wedding_date: Date.new(2026, 10, 25))
  end
  def sample_document(wedding = create_wedding)
    wedding.documents.create!(title: "サンプル", source_type: "email", direction: "incoming", original_text: Analysis::Sample::TEXT, sample: true)
  end
  def analyze_sample(document)
    run = document.analysis_runs.create!(provider: "sample")
    AnalyzeDocumentJob.perform_now(run.id)
    run.reload
  end
  def acceptance_attributes(candidate)
    candidate.payload.slice("title", "description", "assignee", "due_on", "due_at", "category")
  end
  def with_api_env
    old = ENV.to_h.slice("OPENAI_API_KEY", "LLM_MODEL")
    ENV["OPENAI_API_KEY"] = "unit-test-only"
    ENV["LLM_MODEL"] = "test-model"
    yield
  ensure
    %w[OPENAI_API_KEY LLM_MODEL].each { |key| old.key?(key) ? ENV[key] = old[key] : ENV.delete(key) }
  end
end

class ActionDispatch::IntegrationTest
  def sign_in(user)
    post session_path, params: { email: user.email, password: "test-password-12345" }
    assert_response :redirect
  end
end
