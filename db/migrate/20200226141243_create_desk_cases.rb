class CreateDeskCases < ActiveRecord::Migration[5.2]
  def change
    create_table :desk_cases do |t|
      t.string :email
      t.string :subject
      t.text :body
      t.integer :desk_id
      t.integer :freshdesk_id
      t.datetime :case_created_at

      t.timestamps
    end
  end
end
