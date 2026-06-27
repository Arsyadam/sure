import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mailBankFormat", "institutionName", "institutionDomain"]
  static values = { formats: Object }

  connect() {
    if (this.mailBankFormatTarget.value) {
      this.applyFormat(this.mailBankFormatTarget.value)
    }
  }

  updateInstitution() {
    this.applyFormat(this.mailBankFormatTarget.value)
  }

  applyFormat(formatId) {
    const format = this.formatsValue[formatId]
    if (!format) return

    if (this.hasInstitutionNameTarget && format.institution_name) {
      this.institutionNameTarget.value = format.institution_name
    }

    if (this.hasInstitutionDomainTarget && format.institution_domain) {
      this.institutionDomainTarget.value = format.institution_domain
    }
  }
}
