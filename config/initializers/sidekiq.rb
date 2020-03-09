Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] || "redis://localhost:6379/1" }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] || "redis://localhost:6379/1" }
end

hash = {
  # 'Transfer Desk Cases To DB' => {
  #   'class' => Freshdesk::TransferDeskCasesToDB::Worker,
  #   'cron'  => '*/1 * * * *'
  # },
  'Transfer DB Cases To Freshdesk' => {
    'class' => Freshdesk::TransferDBCasesToFreshdesk::Worker,
    'cron'  => '*/1 * * * *'
  }
}

Sidekiq::Cron::Job.load_from_hash! hash unless ENV['NO_SIDEKIQ']
