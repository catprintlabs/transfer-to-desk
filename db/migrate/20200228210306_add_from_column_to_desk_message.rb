class AddFromColumnToDeskMessage < ActiveRecord::Migration[5.2]
  def change
    add_column :desk_messages, :from, :string
  end
end
