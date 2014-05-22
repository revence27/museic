class CreatePlays < ActiveRecord::Migration
  def change
    create_table :plays do |t|
      t.text      :path
      t.timestamp :recent
      t.timestamps
    end
  end
end
