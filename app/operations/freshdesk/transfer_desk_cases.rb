# frozen_string_literal: true

module Freshdesk
  class TransferDeskCases < Base
    UPDATED_BEFORE = '2020-01-18'.to_time.to_i
    CONCURRENCY = 10
    MINUTES_PER_TASK = 3

    class << self
      attr_accessor :end_at
      attr_accessor :cases_processed
      attr_accessor :cases_remaining
    end

    def Base.logger
      @@logger ||= Logger.new(Rails.root.join('log/desk_transfer.log'))
    end

    def self.continous_transfer # for debug... normally we use sidekiq
      loop do
        next_start_time = Time.now + MINUTES_PER_TASK
        logger.info transfer
        sleep next_start_time - Time.now if Time.now < next_start_time
      end
    end

    def self.transfer
      @start_time = Time.now
      @end_at = @start_time + MINUTES_PER_TASK.minutes
      @cases_processed = 0
      Stats.state = "running until #{@end_at}"
      run while keep_going?
      Stats.state = 'stopped'
    end

    def self.keep_going?
      Time.now < end_at
    end

    step :init
    step :grab_cases
    step :initialize_stats
    step :copy_cases_to_freshdesk
    step :complete

    failed :log_failure

    def grab_cases
      succeed!(0) unless TransferDeskCases.keep_going?

      @desk_cases = DeskApi.cases.search(
        sort_field:     :updated_at,
        sort_direction: :desc,
        max_updated_at: UPDATED_BEFORE.to_i,
        channels:       :email
      )
      log_info "Transferring #{@desk_cases.entries.count} entries. "\
               "Entries remaining: #{@desk_cases.total_entries - @desk_cases.entries.count}."
      Stats.cases_remaining = @desk_cases.total_entries
    end

    def initialize_stats
      return if Stats.initialized

      Stats.starting_entries = @desk_cases.total_entries
      Stats.warnings = 0
      Stats.failures = 0
      Stats.transfered = 0
      Stats.skipped = 0
      Stats.initialized = true
    end

    def copy_cases_to_freshdesk
      entries = @desk_cases.entries
      CONCURRENCY.times.map do |group|
        Thread.new do
          Thread.current[:group] = group
          process_every_nth_case(entries, group)
        end
      end.each(&:join)
    end

    def process_every_nth_case(entries, group)
      (group..entries.count - 1).step(CONCURRENCY).each do |index|
        break unless TransferDeskCases.keep_going?

        copy_case_to_freshdesk(index, entries[index])
      end
    end

    def copy_case_to_freshdesk(index, kase, retries = 3)
      return if black_listed(kase)

      log_info "copying #{kase.try(:id)} (#{index + 1} of 50) to freshdesk "
      ticket_id = freshdesk_post('tickets', ticket_hash_for(kase))[:id]
      add_messages(ticket_id, kase)
      touch_case(kase, 'COPIED-TO-FRESHDESK')
      log_info "copied #{kase.try(:id)} to freshdesk ticket #{ticket_id}"
      Stats.transfered += 1
    rescue StandardError => e
      return abort_copy(kase, e) if retries.zero?

      log_warn "case #{kase.try(:id)} encountered error - will retry: #{e}"
      Stats.warnings += 1
      sleep 5.seconds
      copy_case_to_freshdesk(index, kase, retries - 1)
    end

    def black_listed(kase)
      return false unless sender(kase) == 'notify@ringcentral.com'

      Stats.skipped += 1
      touch_case(kase, 'NOT-COPIED-TO-FRESHDESK')
      true
    end

    def touch_case(kase, tag, retries = 3)
      kase.update(labels: [tag])
      TransferDeskCases.cases_processed += 1
      true
    rescue StandardError => e
      return abort_touch if retries.zero?

      log_warn "case #{kase.try(:id)} failed to update, will retry: #{e}"
      Stats.warnings += 1
    end

    def abort_touch(kase)
      log_error "case #{kase.id} could not be updated: #{e}"
      Stat.create(stat: 'untouchable-case', value: kase.id)
    end

    def abort_copy(kase, err)
      log_error "case #{kase.try(:id)} out of retries - moving on: #{err}"
      touch_case(kase, 'FAILED-TO-COPY-TO-FRESHDESK')
      Stat.create(stat: 'failed-to-copy', value: kase.try(:id))
    end

    def add_messages(ticket_id, kase)
      (messages(:note, kase) + messages(:reply, kase))
        .sort { |a, b| a[2] <=> b[2] }.each do |message|
          freshdesk_add_note(ticket_id, format_body(*message))
        end
    end

    def sender(kase)
      emails = DeskApi.customers.find(kase.customer.id).emails
      email_hash = Hash[
        emails.collect { |email| [email['type'], email['value']] }
      ].with_indifferent_access
      email_hash[:home] || email_hash[:work] || email_hash[:other]
    end

    def format_body(note_type, from, created_at, txt)
      "<b>#{first_line(note_type, from)}Created at: #{created_at}.</b>\n\n#{txt}"
        .gsub("\n", "</br>\n")
    end

    def first_line(note_type, from)
      case note_type
      when :original
        "Original message from #{CGI.escapeHTML(from)}.\n"
      when :reply
        "Reply from #{CGI.escapeHTML(from)}.\n"
      when :note
        "Internal Note made by #{CGI.escapeHTML(from)}.\n"
      end
    end

    def ticket_hash_for(kase)
      {
        email:        sender(kase),
        subject:      "#{kase.message.try(:subject)} - Original Desk Case #{kase.id}",
        status:       5,
        priority:     1, # this is required!
        responder_id: nil,
        description:  format_body(:original, sender(kase), kase.created_at, kase.message.try(:body)),
        tags:         ['COPIED-FROM-DESK']
      }
    end

    def messages(kind, kase)
      entries = kase.send({ note: :notes, reply: :replies }[kind]).entries
      entries.collect do |reply|
        from = kind == :note ? reply.try(:user).try(:email) : reply.try(:from)
        next unless reply.try(:body) && from && reply.try(:created_at)

        [kind, from, reply.created_at.to_time, reply.body] unless reply.body.empty?
      end.compact.tap do |filtered_entries|
        log_info "case #{kase.try(:id)}: collected #{entries.count} #{kind}s (#{filtered_entries.count} after filtering)"
      end
    end

    #alias freshdesk_send freshdesk_send_wo_log
  end
end
