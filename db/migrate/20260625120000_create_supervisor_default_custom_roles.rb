class CreateSupervisorDefaultCustomRoles < ActiveRecord::Migration[7.0]
  def up
    Account.find_each do |account|
      Account.create_default_supervisor_role_for_account!(account)
    end
  end

  def down
    Account.find_each do |account|
      role = account.custom_roles.find_by(name: 'Supervisor')
      role&.destroy!
    end
  end
end
