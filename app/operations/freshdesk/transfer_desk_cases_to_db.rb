module Freshdesk
  # transfers cases to db as fast as we can using multiple threads.
  class TransferDeskCasesToDB < Base
    class Worker
      include Sidekiq::Worker
      def perform
        return if ENV['NO_SIDEKIQ']

        Runner.new
      end
    end

    CONCURRENCY = 25
    MINUTES_PER_TASK = 20
    CREATED_BEFORE = '2019-12-02 22:59:11 UTC'.to_time.to_i
    # CREATED_BEFORE = '2012-02-20 14:39:59 UTC'.to_time  # was -17
    # CREATED_BEFORE = DeskCase.last.case_created_at + 10.minutes

    def self.logger
      @logger ||= Logger.new(Rails.root.join('log/desk_transfer.log'))
    end

    class Runner
      class << self
        attr_accessor :heartbeat
        attr_accessor :end_at
        attr_accessor :complete
      end

      def beat!
        Stats.heartbeat = Runner.heartbeat = @heartbeat = Time.now
      end

      def initialize
        TransferDeskCasesToDB.logger.info "attempt to initialize runner, #{Runner.heartbeat}"
        return if Runner.heartbeat && Time.now < Runner.heartbeat + 2.minutes
        return if Runner.complete

        begin
          TransferDeskCasesToDB.logger.info "NO OTHER RUNNERS RUNNING"

          Runner.end_at = Time.now + MINUTES_PER_TASK.minutes
          Stats.state = "running until #{Runner.end_at}"

          while Runner.end_at > Time.now && !Runner.complete
            beat!
            TransferDeskCasesToDB.run(heartbeat: @heartbeat)
            break unless @heartbeat == Runner.heartbeat
          end
          TransferDeskCasesToDB.logger.info "DONE RUNNING..."
        ensure
          Stats.heartbeat = Runner.heartbeat = nil
        end
      end
    end

    param :heartbeat

    def keep_going?
      unless Runner.end_at > Time.now
        log_info 'Stopping: Timed Out'
        return
      end
      unless params.heartbeat == Runner.heartbeat
        log_error "Stopping: Heart Beat Out Of Sync! param: #{params.heartbeat} Runner: #{Runner.heartbeat}"
        return
      end
      if Runner.complete
        log_info 'Stopping: transfer complete'
        return
      end
      true
    end

    step :init
    step :load_cases
    step :initialize_stats
    step :copy_cases_to_db
    step :check_if_transfer_complete
    step :complete

    failed :log_failure

    def load_cases
      succeed!(0) unless keep_going?

      @desk_cases = DeskApi.cases.search(search_criterion)
      @desk_cases_count = @desk_cases.entries.count
      Stats.cases_remaining = @desk_cases.total_entries
      log_info "Transferring #{@desk_cases_count} entries. "\
               "Entries remaining: #{Stats.cases_remaining}."
    rescue DeskApi::Error::TooManyRequests => e
      log_warn "Too Many Requests!  sleeping for #{e.rate_limit.reset_in} seconds"
      sleep e.rate_limit.reset_in
      retry
    end

    def search_criterion
      {
        sort_field: :created_at,
        sort_direction: :asc,
        since_created_at: DeskCase.last_created_at.to_i,
        channels: :email
      }
    end

    def initialize_stats
      return if Stats.initialized

      Stats.starting_entries = @desk_cases.total_entries
      Stats.skipped = 0
      Stats.initialized = true
    end

    def copy_cases_to_db
      entries = @desk_cases.entries
      CONCURRENCY.times.map do |group|
        Thread.new do
          Thread.current[:group] = group
          Thread.current[:operation] = self
          process_every_nth_case(entries, group)
        end
      end.each(&:join)
    end

    def check_if_transfer_complete
      return if @valid_case_found || Runner.end_at <= Time.now

      log_info 'no valid cases found - transfer is complete!'
      Stats.state = Runner.complete = 'transfer complete'
    end

    def process_every_nth_case(entries, group)
      (group..entries.count - 1).step(CONCURRENCY).each do |index|
        break unless keep_going?

        copy_case_to_db(index, entries[index])
      end
    end

    def copy_case_to_db(index, kase)
      retries = 3
      begin
        catch_up_on_sleep
        return unless keep_going?
        return if kase.created_at > CREATED_BEFORE
        return if DeskCase.find_by_desk_id(kase.id)

        @valid_case_found = true
        return if black_listed(kase)

        desk_case = build_from_case(kase)
        add_messages_to_db(desk_case, kase)
        desk_case.save
        log_info "copied #{kase.try(:id)} (#{index + 1} of #{@desk_cases_count}) "\
                 "created_at: #{desk_case.case_created_at} to database "\
                 "(id: #{desk_case.id}, messages: #{desk_case.desk_messages.count})"
      rescue DeskApi::Error::TooManyRequests => e
        return unless keep_going?

        sleep_until e.rate_limit.reset_in
        retry
      rescue StandardError => e
        retries -= 1
        if retries.positive? && keep_going?
          sleep 10.seconds
          retry
        end
        log_error "case #{kase.try(:id)} failed to transfer to database: #{e}"
        DeskCase.create(desk_id: kase.try(:id), failed: e.to_s)
      end
    end

    def sleep_until(sec)
      @sleep_until = Time.now + sec
      log_warn "Too Many Requests!  sleeping until #{@sleep_until} (#{sec} seconds from now)"
    end

    def catch_up_on_sleep
      return unless @sleep_until

      secs = @sleep_until - Time.now
      return unless secs.positive?

      log_info "catching some zzz's"
      sleep secs
      log_info 'wake up!'
    end

    def build_from_case(kase)
      DeskCase.new(
        email: sender(kase),
        subject: kase.message.try(:subject),
        body: kase.message.try(:body),
        desk_id: kase.id,
        case_created_at: kase.created_at
      )
    end

    def black_listed(kase)
      return false unless sender(kase) == 'notify@ringcentral.com'

      Stats.skipped += 1
      true
    end

    def sender(kase)
      Customer.email_from_case(kase)
    end

    def add_messages_to_db(desk_case, kase)
      add_messages(desk_case, kase.notes.entries, kind: :note) do |entry|
        entry.user.email rescue 'agent has been deleted'
      end
      add_messages(desk_case, kase.replies.entries, kind: :reply) do |entry|
        entry.from rescue 'could not find email of sender'
      end
    end

    def add_messages(desk_case, entries, kind:)
      entries.each do |entry|
        from = yield entry
        next unless entry.try(:body).present? && from && entry.try(:created_at)

        desk_case.desk_messages << DeskMessage.new(
          desk_case: desk_case,
          kind: kind, body: entry.try(:body), from: from,
          message_created_at: entry.created_at.to_time
        )
      end
    end
  end

  class ::DeskApi::Request::Retry < Faraday::Middleware
    def call(env)
      retries      = @max
      request_body = env[:body]
      begin
        env[:body] = request_body
        @app.call(env)
      rescue exception_matcher => err
        puts "******************DeskApi catches #{err}.  checking retries #{retries} max: #{@max}"
        raise unless calc(err, retries) { |x| retries = x } > 0

        puts "******************DeskApi catches #{err} will sleep for #{interval(err)}"
        sleep interval(err)
        retry
      end
    end
  end
end
