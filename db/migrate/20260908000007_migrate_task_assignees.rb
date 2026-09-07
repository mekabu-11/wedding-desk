class MigrateTaskAssignees < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE tasks SET assignee = 'person_a' WHERE assignee = 'self'"
    execute "UPDATE tasks SET assignee = 'person_b' WHERE assignee = 'partner'"
    add_check_constraint :tasks, "assignee IN ('person_a', 'person_b', 'both', 'unknown')", name: "tasks_valid_assignee"
  end

  def down
    remove_check_constraint :tasks, name: "tasks_valid_assignee"
    execute "UPDATE tasks SET assignee = 'self' WHERE assignee = 'person_a'"
    execute "UPDATE tasks SET assignee = 'partner' WHERE assignee = 'person_b'"
  end
end
