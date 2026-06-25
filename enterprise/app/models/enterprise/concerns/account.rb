module Enterprise::Concerns::Account
  extend ActiveSupport::Concern

  SUPERVISOR_ROLE_NAME = 'Supervisor'
  SUPERVISOR_ROLE_PERMISSIONS = %w[
    report_manage
    label_manage
    team_manage
    inbox_manage
    conversation_manage
    contact_manage
  ].freeze

  included do
    store_accessor :settings, :conversation_required_attributes

    has_many :sla_policies, dependent: :destroy_async
    has_many :applied_slas, dependent: :destroy_async
    has_many :custom_roles, dependent: :destroy_async
    has_many :agent_capacity_policies, dependent: :destroy_async

    has_many :captain_assistants, dependent: :destroy_async, class_name: 'Captain::Assistant'
    has_many :captain_assistant_responses, dependent: :destroy_async, class_name: 'Captain::AssistantResponse'
    has_many :captain_documents, dependent: :destroy_async, class_name: 'Captain::Document'
    has_many :captain_custom_tools, dependent: :destroy_async, class_name: 'Captain::CustomTool'

    has_many :copilot_threads, dependent: :destroy_async
    has_many :companies, dependent: :destroy_async
    has_many :calls, dependent: :destroy_async

    has_one :saml_settings, dependent: :destroy_async, class_name: 'AccountSamlSettings'

    after_create_commit :create_default_supervisor_role
  end

  class_methods do
    def create_default_supervisor_role_for_account!(account)
      account.custom_roles.find_or_initialize_by(name: SUPERVISOR_ROLE_NAME).tap do |role|
        role.permissions = SUPERVISOR_ROLE_PERMISSIONS
        role.save!
      end
    end
  end

  private

  def create_default_supervisor_role
    self.class.create_default_supervisor_role_for_account!(self)
  end
end
