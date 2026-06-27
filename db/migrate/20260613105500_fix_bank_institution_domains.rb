class FixBankInstitutionDomains < ActiveRecord::Migration[7.2]
  DOMAIN_FIXES = {
    "CIMB" => "cimbniaga.co.id"
  }.freeze

  def up
    DOMAIN_FIXES.each do |code, domain|
      MailBankFormat.find_by(code: code)&.update!(institution_domain: domain)
    end

    Account.where(institution_domain: [ "cimbniaga.com", "www.cimbniaga.co.id", "https://www.cimbniaga.co.id" ])
      .update_all(institution_domain: "cimbniaga.co.id")

    Account.where("institution_domain LIKE 'www.%' OR institution_domain LIKE 'http%'").find_each do |account|
      normalized = Account.normalize_domain(account.institution_domain)
      account.update_column(:institution_domain, normalized) if normalized != account.institution_domain
    end
  end

  def down
    MailBankFormat.find_by(code: "CIMB")&.update!(institution_domain: "cimbniaga.com")
  end
end
