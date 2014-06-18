class CreateMuseicSchedules < ActiveRecord::Migration
  def change
    create_table :museic_schedules do |t|
      t.text        :path
      t.timestamp   :to_run
      t.timestamp   :last_ran
      t.timestamps
    end
  end
end
