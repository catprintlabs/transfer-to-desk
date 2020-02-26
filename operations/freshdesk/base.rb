# frozen_string_literal: true

require 'net/http'
require 'uri'

module Freshdesk
  class Base < Hyperstack::Operation
    RATE_LIMIT_PER_MINUTE = 80

    def self.credentials
      @credentials ||= Rails.application.credentials[:freshdesk]
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
      attr_writer   :rate_limit_remaining
    end

    def self.rate_limit_remaining
      @rate_limit_remaining ||= RATE_LIMIT_PER_MINUTE
    end

    def credentials
      Base.credentials
    end

    def log_header
      @log_header ||=
        "#{self.class}(#{params.to_h.collect { |k, v| "#{k}: #{v.inspect[0..50]}" }.join(', ')}) "
    end

    DIVIDER = '-----------------------------------------------'

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
          Base.logger.send type, "#{log_header} #{message}"
        end
      end
    end

    attr_writer :rate_limit_used

    def rate_limit_used
      @rate_limit_used ||= 0
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

    # override this method if you need to talk to desk live in test cases.

    def talk_to_desk?
      !Rails.env.test?
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
      request.basic_auth(credentials[:account], credentials[:password]) if talk_to_desk?
      request.content_type = 'application/json'
      yield request if block_given?
      freshdesk_send(request).tap do |response|
        Base.rate_limit_remaining = response['X-RateLimit-Remaining'].to_i
        self.rate_limit_used += response['X-Ratelimit-Used-CurrentRequest'].to_i
      end
    end

    def freshdesk_send_wo_log(request)
      response = Net::HTTP.start(request.uri.hostname, request.uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      return response if %w[200 201].include? response.code

      log_warn "#{request} #{request.uri} #{request.body} "\
               "failed with #{response.code} - #{response.body}"
      abort!
    end

    def freshdesk_send(request)
      log_info("request: #{request}")
      freshdesk_send_wo_log(request)
    end
  end
end
