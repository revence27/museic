class CreateMuseicSongs < ActiveRecord::Migration
  def change
    create_table :museic_songs do |t|
      t.text          :path
      t.text          :title
      t.text          :artist
      t.text          :album
      t.text          :sleeve_sha1
      t.integer       :seconds
      t.integer       :year
      t.timestamp     :last_play
      t.timestamps
    end
  end
end
