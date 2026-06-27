module MailSync
  class PatternParser
    def self.parse(html, bank_format)
      new(html, bank_format).parse
    end

    def initialize(html, bank_format)
      @html = html.to_s
      @bank_format = bank_format
      @patterns = bank_format.patterns.is_a?(Hash) ? bank_format.patterns : {}
    end

    def parse
      raise BankEmailParser::ParseError, "HTML email body is empty" if @html.blank?

      BankEmailParser::Parsed.new(
        source: @bank_format.code,
        status: extract("status").presence || "SUCCESS",
        merchant: extract("merchant"),
        amount: parse_amount(extract("amount")),
        date: extract("date"),
        transaction_type: extract("transaction_type")
      )
    end

    private

      def extract(field)
        pattern = @patterns[field.to_s].to_s.strip
        return nil if pattern.blank?

        match = @html.match(Regexp.new(pattern, Regexp::IGNORECASE | Regexp::MULTILINE))
        match&.[](1)&.then { |value| strip_html_comments(value) }
      end

      def parse_amount(raw)
        return nil if raw.blank?

        BankEmailParser.parse_idr_amount(raw)
      end

      def strip_html_comments(text)
        text.to_s.gsub(/<!--.*?-->/, "").gsub(/\s+/, " ").strip
      end
  end
end
