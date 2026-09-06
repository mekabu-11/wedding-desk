module Analysis
  class Error < StandardError
    attr_reader :code
    def initialize(code)
      @code = code
      super(code) # Only an allowlisted code; never a provider response or document text.
    end
  end
end
