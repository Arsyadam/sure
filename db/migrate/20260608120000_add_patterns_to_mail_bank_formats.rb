class AddPatternsToMailBankFormats < ActiveRecord::Migration[7.2]
  def change
    add_column :mail_bank_formats, :patterns, :jsonb, null: false, default: {}
  end
end
