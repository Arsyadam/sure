module AccountableResource
  extend ActiveSupport::Concern

  included do
    include Periodable

    before_action :set_account, only: [ :show, :edit, :update ]
    before_action :set_link_options, only: :new
    before_action :set_mail_sync_context, only: %i[new create edit update]
  end

  class_methods do
    def permitted_accountable_attributes(*attrs)
      @permitted_accountable_attributes = attrs if attrs.any?
      @permitted_accountable_attributes ||= [ :id ]
    end
  end

  def new
    @account = Current.family.accounts.build(
      currency: Current.family.currency,
      accountable: accountable_type.new
    )
  end

  def show
    @chart_view = params[:chart_view] || "balance"
    @q = params.fetch(:q, {}).permit(:search)
    entries = @account.entries.search(@q).reverse_chronological

    @pagy, @entries = pagy(entries, limit: safe_per_page(10))
  end

  def edit
  end

  def create
    @account = Current.family.accounts.create_and_sync(account_params.except(:return_to))
    @account.lock_saved_attributes!

    redirect_to account_params[:return_to].presence || @account, notice: t("accounts.create.success", type: accountable_type.name.underscore.humanize)
  end

  def update
    # Handle balance update if provided
    if account_params[:balance].present?
      result = @account.set_current_balance(account_params[:balance].to_d)
      unless result.success?
        @error_message = result.error_message
        render :edit, status: :unprocessable_entity
        return
      end
      @account.sync_later
    end

    # Update remaining account attributes
    update_params = account_params.except(:return_to, :balance, :currency)
    unless @account.update(update_params)
      @error_message = @account.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
      return
    end

    @account.lock_saved_attributes!
    redirect_back_or_to account_path(@account), notice: t("accounts.update.success", type: accountable_type.name.underscore.humanize)
  end

  private
    def set_link_options
      account_type_name = accountable_type.name

      # Get all available provider configs dynamically for this account type
      @provider_configs = Provider::Factory.connection_configs_for_account_type(
        account_type: account_type_name,
        family: Current.family
      )
    end

    def set_mail_sync_context
      @mail_connection = Current.family.mail_sync_connections.find_by(user: Current.user)
      return unless @mail_connection

      type = @account&.accountable_type || accountable_type.name
      linked_ids = @mail_connection.bank_links.select(:mail_bank_format_id)
      @mail_bank_formats = MailBankFormat.for_accountable_type(type).where(id: linked_ids).ordered

      if @account&.mail_bank_format_id.present? && @mail_bank_formats.none? { |f| f.id == @account.mail_bank_format_id }
        current = MailBankFormat.find_by(id: @account.mail_bank_format_id)
        @mail_bank_formats = [ current, *@mail_bank_formats ].compact.uniq if current
      end

      @mail_bank_format_data = @mail_bank_formats.index_by(&:id).transform_values(&:institution_json)
    end

    def accountable_type
      controller_name.classify.constantize
    end

    def set_account
      @account = Current.family.accounts.find(params[:id])
    end

    def account_params
      params.require(:account).permit(
        :name, :balance, :subtype, :currency, :accountable_type, :return_to,
        :institution_name, :institution_domain, :notes, :account_number_last4, :mail_bank_format_id,
        accountable_attributes: self.class.permitted_accountable_attributes
      )
    end
end
