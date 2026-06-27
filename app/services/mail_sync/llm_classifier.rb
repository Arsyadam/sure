module MailSync
  class LlmClassifier
    def initialize(parsed:, categories:)
      @parsed = parsed
      @categories = categories
    end

    def classify
      Rails.logger.debug("[MailSync] llm.classify merchant=#{@parsed.merchant} amount=#{@parsed.amount} model=#{Configuration.llm_model}")
      response = Faraday.post(Configuration.llm_api_url) do |req|
        req.headers["Authorization"] = "Bearer #{Configuration.llm_api_key}"
        req.headers["Content-Type"] = "application/json"
        req.body = {
          model: Configuration.llm_model,
          temperature: 0,
          stream: false,
          messages: [
            { role: "system", content: "Return ONLY valid JSON. No markdown." },
            { role: "user", content: prompt }
          ]
        }.to_json
      end

      unless response.success?
        Rails.logger.error("[MailSync] llm.classify failed status=#{response.status} body=#{response.body.to_s.truncate(200)}")
        raise StandardError, "LLM request failed (#{response.status})"
      end

      body = parse_response_body(response.body.to_s)
      raw = body.dig("choices", 0, "message", "content").to_s
      result = parse_json(raw)
      Rails.logger.debug("[MailSync] llm.classify ok category=#{result['category_name'] || result['category']}")
      result
    end

    private

      def prompt
        category_names = @categories.map(&:name).join(", ")
        <<~PROMPT.squish
          Classify transaction. Merchant: #{@parsed.merchant}, Amount: #{@parsed.amount},
          Date: #{@parsed.date}, Type: #{@parsed.transaction_type}
          Categories: #{category_names}
          JSON: {"category_name":"...","merchant":"...","amount":0,"date":"YYYY-MM-DD"}
        PROMPT
      end

      def parse_json(raw)
        JSON.parse(raw)
      rescue JSON::ParserError
        cleaned = raw.gsub(/```json|```/, "").strip
        JSON.parse(cleaned)
      end

      def parse_response_body(raw)
        return JSON.parse(raw) unless raw.lstrip.start_with?("data:")

        raw.each_line.filter_map do |line|
          payload = line.strip.delete_prefix("data:").strip
          next if payload.blank? || payload == "[DONE]"

          JSON.parse(payload)
        end.last || raise(StandardError, "LLM returned empty streaming response")
      rescue JSON::ParserError => e
        raise StandardError, "LLM returned invalid JSON: #{e.message}"
      end
  end
end
