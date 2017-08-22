class RolifyCreateRoles < ActiveRecord::Migration[4.2]
  def change
    create_table(:roles, id: false) do |t|
      t.uuid :id, primary_key: true, null: false

      t.string :name
      t.uuid :resource_id
      t.string :resource_type

      t.timestamps
    end

    create_table(:users_roles, id: false) do |t|
      t.uuid :user_id
      t.uuid :role_id
    end

    add_index(:roles, :name)
    add_index(:roles, [:name, :resource_type, :resource_id])
    add_index(:users_roles, [:user_id, :role_id])
  end
end
