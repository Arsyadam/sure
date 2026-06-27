class AddAccountNumberLast4ToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :account_number_last4, :string
    add_index :accounts, [ :family_id, :account_number_last4 ]
  end
end
