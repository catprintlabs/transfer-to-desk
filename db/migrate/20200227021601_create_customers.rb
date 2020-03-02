class CreateCustomers < ActiveRecord::Migration[5.2]
  def change
    create_table :customers do |t|
      t.integer :desk_id
      t.string :email

      t.timestamps
    end
  end
end
