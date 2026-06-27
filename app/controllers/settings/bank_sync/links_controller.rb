class Settings::BankSync::LinksController < ApplicationController
  layout false, only: :new

  before_action :require_connection
  before_action :set_format, only: [ :create ]

  def new
    linked_format_ids = @connection.bank_links.pluck(:mail_bank_format_id)
    @bank_formats = MailBankFormat.enabled.ordered.reject { |f| linked_format_ids.include?(f.id) }
    @card_type_filter = params[:card_type].presence
    @bank_formats = @bank_formats.select { |f| f.card_type == @card_type_filter } if @card_type_filter.present?
  end

  def create
    @connection.bank_links.create!(mail_bank_format: @format)

    redirect_to settings_bank_sync_path,
                notice: t(
                  "settings.bank_sync.links.connected",
                  bank: @format.name,
                  bank_sender: @format.sender_email,
                  gmail: @connection.gmail_email
                ),
                status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to new_settings_bank_sync_link_path,
                alert: e.record.errors.full_messages.to_sentence,
                status: :see_other
  end

  def destroy
    link = @connection.bank_links.find(params[:id])
    bank_name = link.mail_bank_format.name
    link.destroy!
    redirect_to settings_bank_sync_path, notice: t("settings.bank_sync.links.disconnected", bank: bank_name)
  end

  private

    def require_connection
      @connection = Current.family.mail_sync_connections.find_by(user: Current.user)
      unless @connection
        redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.not_connected")
      end
    end

    def set_format
      @format = MailBankFormat.enabled.find_by(id: params[:format_id])
      unless @format
        redirect_to new_settings_bank_sync_link_path, alert: t("settings.bank_sync.links.bank_not_found")
      end
    end
end
