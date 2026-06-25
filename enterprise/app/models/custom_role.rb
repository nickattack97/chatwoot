# == Schema Information
#
# Table name: custom_roles
#
#  id          :bigint           not null, primary key
#  description :string
#  name        :string
#  permissions :text             default([]), is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_custom_roles_on_account_id  (account_id)
#
#

# Available permissions for custom roles:
# - 'conversation_manage': Can manage all conversations.
# - 'conversation_unassigned_manage': Can manage unassigned conversations and assign to self.
# - 'conversation_participating_manage': Can manage conversations they are participating in (assigned to or a participant).
# - 'contact_manage': Can manage contacts.
# - 'report_manage': Can manage reports.
# - 'label_manage': Can manage labels.
# - 'team_manage': Can manage teams.
# - 'inbox_manage': Can manage inboxes.
# - 'campaign_manage': Can manage campaigns.
# - 'knowledge_base_manage': Can manage knowledge base portals.

class CustomRole < ApplicationRecord
  belongs_to :account
  has_many :account_users, dependent: :nullify

  PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_participating_manage
    contact_manage
    report_manage
    label_manage
    team_manage
    inbox_manage
    campaign_manage
    knowledge_base_manage
  ].freeze

  validates :name, presence: true
  validate :validate_permissions

  private

  def validate_permissions
    return if permissions.blank?

    invalid_permissions = permissions - PERMISSIONS
    return if invalid_permissions.empty?

    errors.add(:permissions, "contains invalid permissions: #{invalid_permissions.join(', ')}")
  end
end
