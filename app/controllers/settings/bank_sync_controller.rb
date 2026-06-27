class Settings::BankSyncController < ApplicationController
  layout "settings"

  before_action :ensure_admin, only: [ :update_format ]

  def show
    @providers = external_providers
    @mail_connection = Current.family.mail_sync_connections.find_by(user: Current.user)
    @bank_formats = MailBankFormat.ordered
    @bank_links = if @mail_connection
      @mail_connection.bank_links.includes(:mail_bank_format, :mail_sync_connection).sort_by { |link| link.mail_bank_format.sort_order }
    else
      []
    end
    @mail_sync_configured = MailSync::Configuration.configured?
    events = @mail_connection&.events || MailSyncEvent.none
    @mail_sync_issues = events.issues.recent.limit(20)
    @mail_sync_imports = events.imports.recent.limit(10)
  end

  def connect
    unless MailSync::Configuration.configured?
      redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.not_configured")
      return
    end

    state = SecureRandom.hex(16)
    session[:mail_sync_oauth_state] = state

    redirect_to MailSync::GmailClient.authorization_url(
      state: state,
      redirect_uri: mail_sync_redirect_uri
    ), allow_other_host: true
  end

  def callback
    if params[:error].present?
      redirect_to settings_bank_sync_path, alert: params[:error_description].presence || params[:error]
      return
    end

    unless params[:state].present? && params[:state] == session.delete(:mail_sync_oauth_state)
      redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.invalid_oauth_state")
      return
    end

    token_body = MailSync::GmailClient.exchange_code(
      code: params[:code],
      redirect_uri: mail_sync_redirect_uri
    )

    refresh_token = token_body["refresh_token"]
    unless refresh_token.present?
      redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.missing_refresh_token")
      return
    end

    gmail = MailSync::GmailClient.new(refresh_token: refresh_token)
    gmail_email = gmail.fetch_profile_email

    connection = Current.family.mail_sync_connections.find_or_initialize_by(user: Current.user)
    connection.assign_attributes(
      gmail_email: gmail_email,
      refresh_token: refresh_token,
      bank_codes: [],
      sync_from_at: connection.sync_from_at || Time.current,
      enabled: true
    )
    connection.save!

    if MailSync::Configuration.push_configured?
      MailSync::WatchService.new(connection).start!
    end

    redirect_to settings_bank_sync_path, notice: t("settings.bank_sync.connected", email: gmail_email)
  rescue => e
    Rails.logger.error("Mail sync OAuth callback failed: #{e.message}")
    redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.connect_failed", message: e.message)
  end

  def update
    connection = Current.family.mail_sync_connections.find_by(user: Current.user)
    unless connection
      redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.not_connected")
      return
    end

    codes = Array(params[:bank_codes]).map(&:to_s).map(&:upcase).reject(&:blank?)
    if codes.empty?
      redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.select_at_least_one_bank")
      return
    end

    connection.update!(bank_codes: codes)
    redirect_to settings_bank_sync_path, notice: t("settings.bank_sync.banks_updated")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_bank_sync_path, alert: e.record.errors.full_messages.to_sentence
  end

  def disconnect
    connection = Current.family.mail_sync_connections.find_by(user: Current.user)
    if connection
      MailSync::WatchService.new(connection).stop!
      connection.destroy!
    end

    redirect_to settings_bank_sync_path, notice: t("settings.bank_sync.disconnected")
  end

  def restart_watch
    connection = Current.family.mail_sync_connections.find_by(user: Current.user)
    unless connection
      redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.not_connected")
      return
    end
    unless MailSync::Configuration.push_configured?
      redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.not_configured")
      return
    end

    MailSync::WatchService.new(connection).start!
    redirect_to settings_bank_sync_path, notice: t("settings.bank_sync.watch_restarted")
  rescue => e
    Rails.logger.error("[MailSync] restart_watch failed: #{e.message}")
    redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.watch_restart_failed", message: e.message)
  end

  def update_format
    format = MailBankFormat.find(params[:format_id])
    if format.update(format_params)
      redirect_to settings_bank_sync_path, notice: t("settings.bank_sync.pattern_saved")
    else
      redirect_to settings_bank_sync_path, alert: format.errors.full_messages.to_sentence
    end
  end

  private

    def external_providers
      [
        {
          name: "Lunch Flow",
          description: "US, Canada, UK, EU, Brazil and Asia through multiple open banking providers.",
          path: "https://lunchflow.app/features/sure-integration",
          target: "_blank",
          rel: "noopener noreferrer"
        },
        {
          name: "Plaid",
          description: "US & Canada bank connections with transactions, investments, and liabilities.",
          path: "https://github.com/we-promise/sure/blob/main/docs/hosting/plaid.md",
          target: "_blank",
          rel: "noopener noreferrer"
        },
        {
          name: "SimpleFIN",
          description: "US & Canada connections via SimpleFIN protocol.",
          path: "https://beta-bridge.simplefin.org",
          target: "_blank",
          rel: "noopener noreferrer"
        },
        {
          name: "Enable Banking (beta)",
          description: "European bank connections via open banking APIs across multiple countries.",
          path: "https://enablebanking.com",
          target: "_blank",
          rel: "noopener noreferrer"
        }
      ]
    end

    def mail_sync_redirect_uri
      MailSync::Configuration.oauth_redirect_uri.presence || callback_settings_bank_sync_url
    end

    def format_params
      params.require(:mail_bank_format).permit(:enabled, patterns: MailBankFormat::PATTERN_FIELDS)
    end

    def ensure_admin
      redirect_to settings_bank_sync_path, alert: t("settings.bank_sync.not_authorized") unless Current.user.admin?
    end
end
