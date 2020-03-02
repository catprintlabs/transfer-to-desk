class CreateDeskMessages < ActiveRecord::Migration[5.2]
  def change
    create_table :desk_messages do |t|
      t.text :body
      t.belongs_to :desk_case, foreign_key: true
      t.string :kind
      t.datetime :message_created_at
      t.boolean :copied_to_freshdesk, null: false, default: false

      t.timestamps
    end
  end
end
