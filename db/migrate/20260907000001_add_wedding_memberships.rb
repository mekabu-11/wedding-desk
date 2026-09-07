class AddWeddingMemberships < ActiveRecord::Migration[8.1]
  def up
    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.references :wedding, null: false, foreign_key: true
      t.string :role, null: false, default: "editor"
      t.timestamps
    end

    add_index :memberships, [:wedding_id, :user_id], unique: true
    add_check_constraint :memberships,
      "role IN ('owner', 'editor')",
      name: "memberships_valid_role"

    execute <<~SQL.squish
      INSERT INTO memberships (user_id, wedding_id, role, created_at, updated_at)
      SELECT user_id, id, 'owner', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM weddings
    SQL

    remove_reference :weddings, :user, index: true, foreign_key: true

    # An accepted AI task is a durable work item. Its source candidate may be
    # removed later without making the task invalid.
    remove_check_constraint :tasks, name: "ai_tasks_require_candidate"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "2人目の所属と、削除済み資料から切り離したタスクを安全に元へ戻せません"
  end
end
