require "json_schemer"
module Analysis
  class Validator
    def self.schema
      JSON.parse(Rails.root.join("config/analysis_schema.json").read)
    end
    def self.call(result, document)
      raise Error.new("invalid_output") unless JSONSchemer.schema(schema).valid?(result)
      result.fetch("tasks").each do |item|
        quote = item.fetch("quote")
        offset = document.original_text.index(quote)
        raise Error.new("invalid_evidence") unless offset
        if item["due_on"]
          raise Error.new("invalid_date") unless item["due_on"].match?(/\A\d{4}-\d{2}-\d{2}\z/)
          Date.iso8601(item["due_on"])
        end
        if item["due_at"]
          raise Error.new("invalid_date") unless item["due_at"].match?(/T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})\z/)
          Date.iso8601(item["due_at"].split("T").first)
          Time.iso8601(item["due_at"])
        end
        raise Error.new("invalid_date") if item["due_on"] && item["due_at"]
        if item["original_due_text"].present? && !document.original_text.include?(item["original_due_text"])
          raise Error.new("invalid_evidence")
        end
        item["uncertainty_reasons"] << "期限と担当を原文に照らして確認してください" if item["due_on"] || item["due_at"] || item["assignee"] != "unknown"
      end
      result
    rescue Date::Error, ArgumentError
      raise Error.new("invalid_date")
    end
  end
end
