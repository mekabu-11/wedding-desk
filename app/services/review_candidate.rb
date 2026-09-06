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
      task = document.wedding.tasks.create!(attributes.merge(candidate: candidate, status: "todo"))
      candidate.update!(review_status: "accepted", reviewed_at: Time.current)
      task
    end
  end
end
