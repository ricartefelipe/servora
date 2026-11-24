# frozen_string_literal: true

# Users are global identities (one person may belong to several organizations),
# so this table carries no tenant data and has no RLS policy. Tenant data about
# a person (role, cost, status) lives in memberships.
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :encrypted_password, null: false, default: ""

      t.string :reset_password_token
      t.datetime :reset_password_sent_at

      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string :unconfirmed_email

      t.integer :failed_attempts, null: false, default: 0
      t.string :unlock_token
      t.datetime :locked_at

      t.integer :sign_in_count, null: false, default: 0
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string :current_sign_in_ip
      t.string :last_sign_in_ip

      t.string :otp_secret
      t.integer :consumed_timestep
      t.boolean :otp_required_for_login, null: false, default: false
      t.string :otp_backup_codes, array: true

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :confirmation_token, unique: true
    add_index :users, :unlock_token, unique: true
    add_check_constraint :users, "email = lower(email)", name: "users_email_lowercase"
    add_check_constraint :users, "char_length(name) BETWEEN 1 AND 120", name: "users_name_length"

    # Server-side session registry: every authenticated browser session has a
    # row that can be revoked individually (logout, "end other sessions",
    # deactivation, password change).
    create_table :user_sessions, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.inet :ip_address
      t.string :user_agent, limit: 255
      t.datetime :last_seen_at, null: false
      t.datetime :revoked_at
      t.string :revoke_reason
      t.timestamps
    end

    add_index :user_sessions, %i[user_id revoked_at]
  end
end
