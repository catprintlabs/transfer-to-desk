set :rails_env, 'production'
set :deploy_to, "/var/www/apps/#{fetch(:application)}/production"
set(:branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp })

server "desk-transfer.catprint.com", user: fetch(:user), roles: %w{app db web}

set :ssh_options, forward_agent: true, compression: false, keepalive: true
