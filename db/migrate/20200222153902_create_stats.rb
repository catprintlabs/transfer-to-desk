class CreateStats < ActiveRecord::Migration[5.2]
  def change
    create_table :stats do |t|
      t.string :stat
      t.text :value

      t.timestamps
    end
  end
end
