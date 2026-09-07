class ReviewCandidate
  def self.call(candidate, decision:, attributes: {})
    document = candidate.document
    document.with_lock do
      candidate.reload
      return candidate.task unless candidate.review_status == "pending"
      if decision == "reject"
        candidate.update!(review_status: "rejected", reviewed_at: Time.current)
        return nil
      end
      raise ArgumentError, "invalid_decision" unless decision == "accept"
      source_details = {
        "source_type" => document.source_type,
        "source_title" => document.title,
        "source_occurred_at" => document.occurred_at&.iso8601
      }
      task = document.wedding.tasks.create!(attributes.merge(
        candidate: candidate,
        status: "todo",
        source_details: source_details
      ))
      candidate.update!(review_status: "accepted", reviewed_at: Time.current)
      task
    end
  end
end
