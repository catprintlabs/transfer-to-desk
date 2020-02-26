# frozen_string_literal: true

module Freshdesk
  class TransferDeskCases < Base
    UPDATED_BEFORE = '2020-01-18'.to_time.to_i
    CONCURRENCY = 3
    SAFETY_BUFFER = 500
    AVAILABLE_RATE_LIMIT_PER_HOUR = RATE_LIMIT_PER_HOUR - SAFETY_BUFFER
    RATE_PER_SECOND = AVAILABLE_RATE_LIMIT_PER_HOUR / 3600.0
    MINUTES_PER_TASK = 5

    class << self
      attr_accessor :end_at
      attr_accessor :rate_limit_used
      attr_accessor :cases_processed
    end

    def Base.logger
      @logger ||= Logger.new(Rails.root.join('log/desk_transfer.log'))
    end

    def self.continous_transfer
      loop do
        next_start_time = Time.now + MINUTES_PER_TASK
        logger.info transfer
        sleep next_start_time - Time.now if Time.now < next_start_time
      end
    end

    def self.transfer
      Base.rate_limit_remaining = nil # forces it to be recalcuated on each run
      @start_time = Time.now
      @end_at = @start_time + MINUTES_PER_TASK.minutes
      @rate_limit_used = 0
      @cases_processed = 0
      while keep_going?
        run
        throttle
      end
      stats
    end

    def self.throttle
      # freshdesk rate limit resets at the half hour mark
      seconds_since_reset = Time.now + 30.minutes - (Time.now + 30.minutes).change(min: 0)
      actual_seconds_used = (RATE_LIMIT_PER_HOUR - Base.rate_limit_remaining) /
                            RATE_PER_SECOND
      sleep_time = actual_seconds_used - seconds_since_reset

      logger.info "Throttling - minutes since reset: #{seconds_since_reset / 60.0} "\
                  "minutes used since reset: #{actual_seconds_used / 60.0} "\
                  "sleep time to catchup: #{sleep_time}"
      sleep sleep_time if sleep_time.positive?
    end

    def self.stats
      total_time = Time.now - @start_time
      {
        cases_remaining:      @cases_remaining,
        cases_processed:      @cases_processed,
        rate_limit_used:      @rate_limit_used,
        total_time:           total_time,
        cases_per_hour:       (@cases_processed.to_f / total_time) * 3600,
        rate_limit_remaining: Base.rate_limit_remaining,
        rate_limit_per_hour:  (@rate_limit_used.to_f / total_time) * 3600,
        requests_per_case:    @cases_processed.zero? ? 0 : @rate_limit_used.to_f / @cases_processed
      }
    end

    def self.keep_going?
      Base.rate_limit_remaining > SAFETY_BUFFER && Time.now < end_at
    end

    step :init
    step :grab_cases
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
    end

    def copy_cases_to_freshdesk
      entries = @desk_cases.entries
      CONCURRENCY.times.map do |group|
        Thread.new do
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

      log_info "copying #{kase.try(:id)} (#{index + 1} of 50) to freshdesk - "\
               "rate_limit_remaining: #{Base.rate_limit_remaining}"
      ticket_id = freshdesk_post('tickets', ticket_hash_for(kase))[:id]
      add_messages(ticket_id, kase)
      touch_case(kase, 'COPIED-TO-FRESHDESK')
      log_info "copied #{kase.try(:id)} to freshdesk ticket #{ticket_id}"
    rescue StandardError => e
      return abort_copy(kase, e) if retries.zero?

      log_warn "case #{kase.try(:id)} encountered error - will retry: #{e}"
      sleep 5.seconds
      copy_case_to_freshdesk(index, kase, retries - 1)
    end

    def black_listed(kase)
      return false unless sender(kase) == 'notify@ringcentral.com'

      touch_case(kase, 'NOT-COPIED-TO-FRESHDESK')
      true
    end

    def touch_case(kase, tag, retries = 3)
      kase.update(labels: [tag])
      TransferDeskCases.cases_processed += 1
      true
    rescue StandardError => e
      return log_error "case #{kase.id} could not be updated: #{e}" if retries.zero?

      log_warn "case #{kase.try(:id)} failed to update, will retry: #{e}"
    end

    def abort_copy(kase, err)
      log_error "case #{kase.try(:id)} out of retries - moving on: #{err}"
      touch_case(kase, 'FAILED-TO-COPY-TO-FRESHDESK')
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

    alias freshdesk_send freshdesk_send_wo_log
  end
end
