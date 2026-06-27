module MailSync
  class BankEmailParser
    ParseError = Class.new(StandardError)

    Parsed = Struct.new(:source, :status, :merchant, :amount, :date, :transaction_type, keyword_init: true)

    def self.parse(html, bank_format:)
      if bank_format.patterns_enabled?
        PatternParser.parse(html, bank_format)
      else
        new(html, parser: bank_format.parser, source: bank_format.code).parse
      end
    end

    def initialize(html, parser:, source:)
      @html = html.to_s
      @parser = parser.to_s
      @source = source.to_s.upcase
    end

    def parse
      raise ParseError, "HTML email body is empty" if @html.blank?

      parsed = case @parser
      when "bca" then parse_bca
      when "cimb" then parse_cimb
      when "jago" then parse_jago
      when "gopay" then parse_gopay
      when "mandiri" then parse_mandiri
      when "jenius_credit" then parse_jenius_credit
      when "mega_credit" then parse_mega_credit
      else
                 raise ParseError, "Unknown parser: #{@parser}"
      end

      parsed.source = @source
      parsed
    end

    private

      def parse_jago
        merchant = extract_jago_table_field("Ke")
        amount_raw = extract_jago_table_field("Jumlah")
        amount = amount_raw ? parse_idr_amount(amount_raw) : nil
        raise ParseError, "Jago amount not found" if amount.nil?

        Parsed.new(
          source: @source,
          status: extract_jago_table_field("Status Transaksi") || "Berhasil",
          merchant: merchant,
          amount: amount,
          date: extract_jago_table_field("Tanggal Transaksi"),
          transaction_type: extract_jago_table_field("Nama Acquirer")
        )
      end

      def extract_jago_table_field(label)
        pattern = /transfer-table-title">#{Regexp.escape(label)}<\/p>[\s\S]*?transfer-table-content">([^<]+)/i
        @html[pattern, 1]&.strip
      end

      def parse_gopay
        amount = extract_gopay_amount
        raise ParseError, "GoPay amount not found" if amount.nil?

        Parsed.new(
          source: @source,
          status: "SUCCESS",
          merchant: extract_gopay_merchant,
          amount: amount,
          date: extract_gopay_date,
          transaction_type: "Pembayaran"
        )
      end

      def extract_gopay_amount
        raw = @html[/Total Pembayaran[\s\S]*?<td[^>]*>\s*(Rp\s*[\d.,]+)/i, 1]
        raw ||= @html[/class="amount-paid"[^>]*>\s*(Rp\s*[\d.,]+)/i, 1]
        raw ? parse_idr_amount(raw) : nil
      end

      def extract_gopay_merchant
        operator = @html[/id="operator-name"[^>]*>\s*([^<]+)/i, 1]&.strip
        product = @html[/font-weight:\s*bold[^>]*>\s*((?:Pulsa|Paket)[^<]+)/i, 1]&.strip

        if operator.present?
          [ operator, product ].compact.join(" ").presence
        else
          @html[/class="merchant-name"[^>]*>([^<]+)/i, 1]&.strip || "GoPay"
        end
      end

      def extract_gopay_date
        @html[/>([A-Za-z]+day \d{1,2} [A-Za-z]+ \d{4})</, 1] ||
          @html[/>(\d{1,2} [A-Za-z]+ \d{4})</, 1]
      end

      def parse_bca
        data = {}
        @html.scan(/<td[^>]*>([^<:]+)<\/td>\s*<td[^>]*>:\s*<\/td>\s*<td[^>]*>([^<]+)<\/td>/m) do |key, value|
          data[key.strip] = value.strip
        end

        raw_amount = data["Total Payment"].to_s
        amount = parse_idr_amount(raw_amount)

        Parsed.new(
          source: @source,
          status: data["Status"],
          merchant: data["Payment to"],
          amount: amount,
          date: data["Transaction Date"],
          transaction_type: data["Transaction Type"]
        )
      end

      def parse_cimb
        pairs = extract_cimb_pairs

        raw_amount = pairs["Total Payment:"] || pairs["Transfer Amount"] || pairs["Transfer Amount:"]
        merchant = pairs["Merchant Name:"] || pairs["Beneficiary Name:"]
        merchant = strip_html_comments(merchant)

        Parsed.new(
          source: @source,
          status: pairs["Status:"].presence || "SUCCESS",
          merchant: merchant,
          amount: raw_amount ? parse_idr_amount(raw_amount) : nil,
          date: pairs["Date/Time:"],
          transaction_type: pairs["Purchase Type:"] || pairs["Transfer Type:"]
        )
      end

      def extract_cimb_pairs
        pairs = {}
        @html.scan(/class="text-paramname"[^>]*>\s*([\s\S]*?)\s*<\/td>[\s\S]*?class="text-paramvalue"[^>]*>\s*([\s\S]*?)\s*<\/td>/i) do |key, value|
          normalized_key = key.gsub(/\s+/, " ").strip
          normalized_value = strip_html_comments(value.gsub(/\s+/, " ").strip)
          pairs[normalized_key] = normalized_value
        end
        pairs
      end

      def strip_html_comments(text)
        text.to_s.gsub(/<!--.*?-->/, "").gsub(/\s+/, " ").strip
      end

      def parse_mandiri
        merchant = @html[/<p[^>]*>\s*Penerima\s*<\/p>\s*<h4[^>]*>\s*([^<]+)/i, 1]&.strip
        merchant ||= @html[/<h4[^>]*>\s*([^<]+)\s*<\/h4>/i, 1]&.strip

        amount_raw = extract_label_value("Nominal Transaksi")
        amount = amount_raw ? parse_idr_amount(amount_raw) : nil
        raise ParseError, "Mandiri amount not found" if amount.nil?

        date = extract_label_value("Tanggal")
        time = extract_label_value("Jam")
        combined_date = [ date, time ].compact.join(" ").presence

        Parsed.new(
          source: @source,
          status: "Berhasil",
          merchant: merchant,
          amount: amount,
          date: combined_date,
          transaction_type: "QRIS"
        )
      end

      def parse_jenius_credit
        merchant = @html[/Merchant:\s*([^<]+)/i, 1]&.strip
        amount_raw = @html[/Total Transaksi:\s*(Rp[^<]+)/i, 1]
        amount = amount_raw ? parse_idr_amount(amount_raw) : nil
        raise ParseError, "Jenius amount not found" if amount.nil?

        Parsed.new(
          source: @source,
          status: "Berhasil",
          merchant: merchant,
          amount: amount,
          date: @html[/Tanggal & waktu transaksi:\s*([^<]+)/i, 1]&.strip,
          transaction_type: "Kartu Kredit"
        )
      end

      def parse_mega_credit
        pairs = extract_mega_pairs
        amount_raw = pairs["Total Transaksi"]
        amount = amount_raw ? parse_idr_amount(amount_raw) : nil
        raise ParseError, "Mega amount not found" if amount.nil?

        Parsed.new(
          source: @source,
          status: pairs["Status Transaksi"].presence || "Berhasil",
          merchant: pairs["Merchant"],
          amount: amount,
          date: pairs["Waktu Transaksi"],
          transaction_type: "Kartu Kredit"
        )
      end

      def extract_mega_pairs
        pairs = {}
        @html.scan(/<tr>\s*<td>([^<]+)<\/td>\s*<td>:\s*([^<]+)<\/td>\s*<\/tr>/i) do |key, value|
          pairs[key.strip] = value.strip
        end
        pairs
      end

      def extract_label_value(label)
        pattern = />#{Regexp.escape(label)}<\/td>\s*<td[^>]*>([^<]+)</i
        @html[pattern, 1]&.strip
      end

    def self.parse_idr_amount(raw)
      cleaned = raw.to_s.gsub(/IDR|Rp\.?\s*/i, "").strip
      if cleaned.match?(/\d+\.\d{3},\d{2}/)
        cleaned = cleaned.gsub(".", "").gsub(",", ".")
      elsif cleaned.include?(",") && cleaned.include?(".")
        cleaned = cleaned.gsub(",", "")
      else
        cleaned = cleaned.gsub(".", "").gsub(",", ".")
      end
      Float(cleaned)
    rescue ArgumentError, TypeError
      nil
    end

    def parse_idr_amount(raw)
      self.class.parse_idr_amount(raw)
    end
  end
end
