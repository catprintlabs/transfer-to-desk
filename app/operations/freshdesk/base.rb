# frozen_string_literal: true

module Freshdesk
  PRELOAD = [Customer, DeskCase, DeskMessage].freeze # see https://github.com/rails/rails/issues/33209
  class Base < Hyperstack::ServerOp

    SAFETY_MARGIN = 10.0

    require 'net/http'
    require 'uri'

    def self.credentials
      @@credentials ||= Rails.application.credentials[:freshdesk]
    end

    def self.logger
      @logger ||= Logger.new(Rails.root.join('log/freshdesk.log'))
    end

    def self.[](*args)
      run(*args).value
    end

    class << self
      attr_accessor :agents
      attr_accessor :settings
    end

    def credentials
      Base.credentials
    end

    def log_header
      @log_header ||=
        "#{self.class}(#{params.to_h.collect { |k, v| "#{k}: #{v.inspect[0..50]}" }.join(', ')}) "
    end

    DIVIDER = '-----------------------------------------------'

    @@throttle_lock      = Mutex.new
    @@throttle_data_lock = Mutex.new
    @@rate_limit_total = nil
    @@rate_limit_remaining = nil

    def init
      log_info DIVIDER
    end

    def complete(ret_value = nil)
      log_info 'Complete.'
      log_info "#{DIVIDER}\n\n"
      ret_value
    end

    def log_failure(err = nil)
      if err
        log_error "Failed with #{err}."
      else
        log_error 'Aborted.'
      end
      log_info "#{DIVIDER}\n\n"
      err
    end

    def succeed!(*)
      complete
      super
    end

    def abort!(arg = nil)
      log_failure(arg)
      super
    end

    %i[info error warn].each do |type|
      define_method :"log_#{type}" do |*messages|
        messages.each do |message|
          self.class.logger.send type, "#{Thread.current[:group].to_s.rjust(2)} #{log_header} #{message}"
        end
      end
    end

    def freshdesk_get(path)
      JSON.parse(freshdesk_api(Net::HTTP::Get, path).body, symbolize_names: true)
    end

    def freshdesk_put(path, opts)
      freshdesk_api(Net::HTTP::Put, path) do |request|
        request.body = JSON.dump(opts)
      end
    end

    def freshdesk_post(path, opts)
      JSON.parse(
        freshdesk_api(Net::HTTP::Post, path) do |request|
          request.body = JSON.dump(opts)
        end.body,
        symbolize_names: true
      )
    end

    def agent_id(name)
      agents[name] || agents(reload: true)[name]
    end

    def freshdesk_add_note(ticket_id, body)
      freshdesk_post("tickets/#{ticket_id}/notes", body: body, private: true)
    end

    def agents(*, reload: false)
      # first param is ignored, allowing agents to be called in the step chain.
      Base.agents = false if reload
      Base.agents ||= Rails.cache.fetch('freshdesk-current-agent-ids', force: reload) do
        agents = freshdesk_get('agents')
        Hash[agents.collect { |agent| [agent[:contact][:name], agent[:id]] }].tap do |agent_hash|
          log_info "agent cache miss, reload: #{!!reload}"
          agent_hash.each { |name, id| log_info "    #{name.ljust(20)} #{id}" }
        end
      end
    end

    private

    def freshdesk_api(operation, path)
      uri = URI.parse("#{credentials[:endpoint]}#{path}")
      request = operation.new(uri)
      request.basic_auth(credentials[:account], credentials[:password])
      request.content_type = 'application/json'
      yield request if block_given?
      throttle(request)
    end

    def locking_sleep(time)
      return unless time.positive?

      end_at = Time.now + time
      log_info "sleeping until #{end_at}"
      while Time.now < end_at
      end
    end

    def throttle(request)
      @@throttle_lock.synchronize do
        locking_sleep(@@throttle_data_lock.synchronize { compute_throttle_time })
      end
      freshdesk_send(request).tap do |response|
        @@throttle_data_lock.synchronize { capture_throttle_data(response) }
      end
    end

    def elapsed_cycle_time
      Time.now - @@cycle_started_at
    end

    def compute_throttle_time
      compute_throttle_time_wo_log.tap do |throttle_time|
        log_info "throttling for #{throttle_time} seconds" unless throttle_time.zero?
      end
    end

    10/10
    10/9

    def compute_throttle_time_wo_log
      if @@rate_limit_total.nil?
        throttle_time = 2 # if we use a non-blocking sleep then this should be something like the group number
        # so that the initial requests are spread out 1 second apart
        log_info('rate limit not set, default to 2 seconds')
      else
        transmissions = @@rate_limit_at_cycle_start - @@rate_limit_remaining
        target_seconds_per_request = 60 / (@@rate_limit_total * 0.8)
        actual_seconds_per_request =
          transmissions.positive? ? elapsed_cycle_time / transmissions : 0

        target_elapsed_seconds = transmissions * 60.0 / (@@rate_limit_total - SAFETY_MARGIN)
        if @@rate_limit_remaining < SAFETY_MARGIN / 2.0
          brakes = 20
        else
          brakes = SAFETY_MARGIN.to_f / @@rate_limit_remaining
        end
        throttle_time = [target_elapsed_seconds - elapsed_cycle_time, 0].max + brakes
        log_info("will throttle for #{throttle_time} target: #{target_elapsed_seconds} actual: #{elapsed_cycle_time} brakes: #{brakes}")
      end
      throttle_time
    end

    def capture_throttle_data(response)
      @@rate_limit_total = response['X-Ratelimit-Total'].to_i
      remaining = response['X-RateLimit-Remaining'].to_i
      if @@rate_limit_remaining.nil? || remaining > @@rate_limit_remaining + 10
        @@rate_limit_at_cycle_start = remaining
        @@cycle_started_at = Time.now
        cycle_restarted = true
      end
      @@rate_limit_remaining = remaining
      log_throttle_data(cycle_restarted)
      response
    end

    def log_throttle_data(cycle_restarted)
      log_info "rate_limit_total: #{@@rate_limit_total} "\
               "rate_limit_at_cycle_start: #{@@rate_limit_at_cycle_start} "\
               "cycle started at: #{@@cycle_started_at} "\
               "remaining: #{@@rate_limit_remaining}"\
               "#{' CYCLE RESTARTED!' if cycle_restarted}"
    end

    def freshdesk_send_wo_log(request)
      response = Net::HTTP.start(request.uri.hostname, request.uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      return response if %w[200 201].include? response.code

      raise "#{request} #{request.uri} #{request.body} "\
               "failed with #{response.code} - #{response.body}"
    end

    def freshdesk_send(request)
      log_info("request: #{request}")
      freshdesk_send_wo_log(request)
    end
  end
end
