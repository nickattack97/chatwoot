# The default Supervisor role now includes campaign_manage. Add it to the roles already seeded
# on existing accounts, keeping any other permissions an administrator has changed.
class AddCampaignManageToSupervisorCustomRoles < ActiveRecord::Migration[8.0]
  def up
    CustomRole.where(name: 'Supervisor').find_each do |role|
      next if role.permissions.include?('campaign_manage')

      role.update!(permissions: role.permissions + ['campaign_manage'])
    end
  end

  def down
    CustomRole.where(name: 'Supervisor').find_each do |role|
      role.update!(permissions: role.permissions - ['campaign_manage'])
    end
  end
end
