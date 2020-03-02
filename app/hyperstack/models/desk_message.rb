class DeskMessage < ApplicationRecord
  default_scope { order(message_created_at: :asc) }
  belongs_to :desk_case
end
