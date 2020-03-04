# frozen_string_literal: true

app_dir = File.expand_path('../..', __FILE__)

env = ENV.fetch('RAILS_ENV') { 'development' }
environment env

workers ENV.fetch('WEB_CONCURRENCY') { 0 }

threads_count = ENV.fetch('RAILS_MAX_THREADS') { 5 }
threads threads_count, threads_count

if (bind_socket = ENV.fetch('BIND_SOCKET') { nil })
  bind bind_socket
else
  port ENV.fetch('PORT') { 3000 }, ENV.fetch('HOST') { nil }
end

# Specifies the `pidfile` that Puma will use.
pidfile ENV.fetch('PIDFILE') { 'tmp/pids/server.pid' }

state_path ENV.fetch('STATE_PATH') { 'tmp/pids/puma.state' }

# Logging
if %w[staging production].include?(env)
  stdout_redirect 'log/puma.stdout.log', 'log/puma.stderr.log', true
end

preload_app!

on_worker_boot do
  ActiveSupport.on_load(:active_record) do
    ActiveRecord::Base.establish_connection
  end
end

tag "transfer-to-desk-#{env}"

activate_control_app ENV.fetch('CONTROL_APP_SOCKET') { 'tcp://127.0.0.1:3001' },
                     auth_token: ENV.fetch('PUMA_TOKEN') { 'password' }
