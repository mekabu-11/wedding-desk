module CrossDocumentAi
  class Error < StandardError; end

  # The default adapter never exports document data. A provider adapter can be
  # supplied to Prepare in an explicitly configured deployment.
  class Adapter
    def self.configured?
      false
    end

    def call(_document)
      raise Error, "cross_ai_provider_not_configured"
    end
  end
end
