module MailSync
  class CategoryResolver
    def initialize(parsed:, categories:)
      @parsed = parsed
      @categories = categories
    end

    def resolve
      llm_result = LlmClassifier.new(parsed: @parsed, categories: @categories).classify
      category = find_category(llm_result["category_name"].presence || llm_result["category"].to_s)
      raise StandardError, "Category not found: #{llm_result}" unless category

      {
        category: category,
        merchant: llm_result["merchant"].presence || @parsed.merchant,
        amount: llm_result["amount"].presence || @parsed.amount,
        date: llm_result["date"].presence || @parsed.date
      }
    end

    private

      def find_category(name)
        return nil if name.blank?

        @categories.find { |c| c.name.casecmp?(name) }
      end
  end
end
