# config valid for current version and patch releases of Capistrano
lock "~> 3.12.0"

set :user, 'deploy'
set :application, "transfer-to-desk"
set :repo_url, 'git@github.com:catprintlabs/transfer-to-desk.git'
set :stages, %w[production]
set :keep_releases, 4

append :linked_files, 'config/master.key', '.env.production'
append :linked_dirs, 'log', 'tmp'

# rbenv
set :rbenv_type, :user
set :rbenv_ruby, '2.6.3'
set :rbenv_prefix, "RBENV_ROOT=#{fetch(:rbenv_path)} RBENV_VERSION=#{fetch(:rbenv_ruby)} "\
                   "#{fetch(:rbenv_path)}/bin/rbenv exec"
set :rbenv_map_bins, %w[rake gem bundle ruby rails puma pumactl sidekiqctl]
set :rbenv_roles, :all # default value

namespace :deploy do
  task :restart_app do
    on roles(:app) do
      execute(:sudo, 'restart-app', '-e', fetch(:stage), fetch(:application))
    end
  end
end

after 'deploy:reverted', 'deploy:restart_app'
after 'deploy:published', 'deploy:restart_app'
