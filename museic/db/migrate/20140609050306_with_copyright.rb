class WithCopyright < ActiveRecord::Migration
  def change
    add_column :museic_songs, :copyright, :text
  end
end
