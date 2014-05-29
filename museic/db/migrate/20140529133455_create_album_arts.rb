class CreateAlbumArts < ActiveRecord::Migration
  def change
    create_table :album_arts do |t|
      t.text          :sha1_sig
      t.text          :content_type
      t.binary        :rawdata
      t.timestamps
    end
  end
end
