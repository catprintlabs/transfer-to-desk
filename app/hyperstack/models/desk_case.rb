class DeskCase < ApplicationRecord
  scope :successful, -> { order(case_created_at: :asc).where('failed IS NULL') }
  scope :failed, -> { order(created_at: :desc).where('failed IS NOT NULL') }

  scope :ready_to_transfer, -> { successful.where('freshdesk_id IS NULL') }

  scope :completed, -> { order(case_created_at: :asc).where('freshdesk_id IS NOT NULL') }

  scope :completed_order_by_updated_at, -> { order(updated_at: :asc).where('freshdesk_id IS NOT NULL') }
  scope :order_by_created_at, -> { order(created_at: :asc) }

  has_many :desk_messages

  def self.last_created_at
    return Time.parse('2012-07-16 11:45:44 UTC') unless last

    where('case_created_at IS NOT NULL').order(case_created_at: :asc).last.case_created_at
  end

  attr_accessor :kase

  def self.create_from_case(kase)
    DeskCase.new(
      email: Customer.email_from_case(kase),
      subject: kase.message.try(:subject),
      body: kase.message.try(:body),
      desk_id: kase.id,
      case_created_at: kase.created_at,
      kase: kase
    ).add_messages.tap(&:save)
  end

  def add_messages
    add_messages_helper(kase.notes.entries, kind: :note) do |entry|
      entry.try(:user).try(:email)
    end
    add_messages_helper(kase.replies.entries, kind: :reply) do |entry|
      entry.try(:from)
    end
    self
  end

  def add_messages_helper(entries, kind:)
    entries.each do |entry|
      from = yield entry
      next unless entry.try(:body).present? && from && entry.try(:created_at)

      desk_messages << DeskMessage.new(
        body: entry.try(:body),
        kind: kind,
        message_created_at: entry.created_at.to_time
      )
    end
  end
end
