class Provider::Openai::GenericChatParser
  Error = Class.new(StandardError)

  def initialize(object)
    @object = normalize_object(object)
  end

  def parsed
    ChatResponse.new(
      id: response_id,
      model: response_model,
      messages: messages,
      function_requests: function_requests
    )
  end

  private
    attr_reader :object

    def normalize_object(value)
      return value unless value.is_a?(String)

      stripped = value.strip

      # SSE: "data: {...}\n\ndata: [DONE]" (some proxies send this for non-stream requests too)
      if stripped.include?("data:")
        payload = stripped.scan(/^data:\s*(.+)$/m).flatten.map(&:strip).find { |chunk| chunk.start_with?("{") }
        return JSON.parse(payload) if payload.present?

        # Concatenated JSON + SSE suffix, e.g. '{...}data: ...'
        stripped = stripped.split("data:", 2).first.to_s.strip
      end

      JSON.parse(stripped)
    rescue JSON::ParserError => e
      raise Error, "Expected JSON chat response, got: #{value.to_s.truncate(200)} (#{e.message})"
    end

    ChatResponse = Provider::LlmConcept::ChatResponse
    ChatMessage = Provider::LlmConcept::ChatMessage
    ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

    def response_id
      object.dig("id")
    end

    def response_model
      object.dig("model")
    end

    def message_choice
      object.dig("choices", 0, "message")
    end

    def messages
      content = message_choice&.dig("content")
      return [] if content.blank?

      [
        ChatMessage.new(
          id: response_id,
          output_text: content
        )
      ]
    end

    def function_requests
      tool_calls = message_choice&.dig("tool_calls") || []

      tool_calls.map do |tool_call|
        ChatFunctionRequest.new(
          id: tool_call.dig("id"),
          call_id: tool_call.dig("id"),
          function_name: tool_call.dig("function", "name"),
          function_args: tool_call.dig("function", "arguments")
        )
      end
    end
end
