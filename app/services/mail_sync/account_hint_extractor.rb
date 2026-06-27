module MailSync
  class AccountHintExtractor
    PATTERNS = [
      /\d{6}\*{2,}(\d{4})/,
      /\*{2,}(\d{4})/,
      /x{2,}(\d{4})/i,
      /\#{2,}(\d{4})/i
    ].freeze

    def self.extract(html)
      text = html.to_s
      hints = PATTERNS.flat_map do |pattern|
        text.scan(pattern).map { |match| Array(match).last.to_s }
      end

      hints.map { |hint| hint.gsub(/\D/, "") }.select { |hint| hint.length == 4 }.uniq
    end
  end
end
