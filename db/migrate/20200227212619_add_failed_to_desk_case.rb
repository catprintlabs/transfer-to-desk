class AddFailedToDeskCase < ActiveRecord::Migration[5.2]
  def change
    add_column :desk_cases, :failed, :string
  end
end
