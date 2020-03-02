# frozen_string_literal: true

module Freshdesk
  class TransferDBCasesToFreshdesk < Base
    class Worker
      include Sidekiq::Worker
      def perform
        return if ENV['NO_SIDEKIQ']

        Runner.new
      end
    end

    CONCURRENCY = 5
    MINUTES_PER_TASK = 1

    class << self
      attr_accessor :end_at
      attr_accessor :cases_processed
      attr_accessor :cases_remaining
    end

    def self.logger
      @logger ||= Logger.new(Rails.root.join('log/transfer_from_db.log'))
    end

    class Runner
      class << self
        attr_accessor :heartbeat
        attr_accessor :end_at
      end

      def beat!
        Stats.tofreshdesk_heartbeat = Runner.heartbeat = @heartbeat = Time.now
      end

      def initialize
        TransferDBCasesToFreshdesk.logger.info "attempt to initialize runner, #{Runner.heartbeat}"
        return if Runner.heartbeat && Time.now < Runner.heartbeat + 2.minutes

        begin
          TransferDBCasesToFreshdesk.logger.info "NO OTHER RUNNERS RUNNING"

          Runner.end_at = Time.now + MINUTES_PER_TASK.minutes
          Stats.tofreshdesk_state = "running until #{Runner.end_at}"

          while Runner.end_at > Time.now && DeskCase.ready_to_transfer(0).first
            beat!
            TransferDBCasesToFreshdesk.run
          end
          TransferDBCasesToFreshdesk.logger.info "DONE RUNNING..."
        ensure
          Stats.tofreshdesk_heartbeat = Runner.heartbeat = nil
        end
      end
    end

    step :init
    step :copy_cases_to_freshdesk
    step :complete

    failed :log_failure

    def copy_cases_to_freshdesk
      CONCURRENCY.times.map do |group|
        Thread.new do
          Thread.current[:group] = group
          copy_case_to_freshdesk(DeskCase.ready_to_transfer(group).first)
        end
      end.each(&:join)
    end

    def copy_case_to_freshdesk(kase)
      return unless kase
      retries = 3
      begin
        log_info "copying #{kase.desk_id} to freshdesk "
        ticket_id = freshdesk_post('tickets', ticket_hash_for(kase))[:id]
        add_messages(ticket_id, kase)
        kase.update(freshdesk_id: ticket_id)
        log_info "copied #{kase.desk_id} to freshdesk ticket #{ticket_id}"
      rescue StandardError => e
        return abort_copy(kase, e) if retries.zero?

        log_warn "case #{kase.desk_id} encountered error - will retry: #{e}"
        Stats.tofreshdesk_warnings += 1
        sleep 5.seconds
        retry
      end
    end

    def abort_copy(kase, err)
      log_error "case #{kase.desk_id} out of retries - moving on: #{err}"
      kase.update(failed: err.to_s)
    end

    def add_messages(ticket_id, kase)
      kase.desk_messages.each do |message|
        freshdesk_add_note(
          ticket_id,
          format_body(message.kind, message.from, message.message_created_at, message.body)
        )
      end
    end

    def format_body(note_type, from, created_at, txt)
      "<b>#{first_line(note_type, from)}Created at: #{created_at}.</b>\n\n#{txt}"
        .gsub("\n", "</br>\n")
    end

    def first_line(note_type, from)
      case note_type.to_sym
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
        email:        kase.email,
        subject:      kase.subject,
        status:       5,
        priority:     1, # this is required!
        responder_id: nil,
        description:  format_body(:original, kase.email, kase.case_created_at, kase.body),
        tags:         ['COPIED-FROM-DESK-2']
      }
    end

    #alias freshdesk_send freshdesk_send_wo_log
  end
end
