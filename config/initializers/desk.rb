DeskApi.configure do |config|
  config.token           = Rails.application.credentials[:desk][:token]
  config.token_secret    = Rails.application.credentials[:desk][:token_secret]
  config.consumer_key    = Rails.application.credentials[:desk][:consumer_key]
  config.consumer_secret = Rails.application.credentials[:desk][:consumer_secret]
  config.subdomain       = Rails.application.credentials[:desk][:subdomain]
  config.endpoint        = Rails.application.credentials[:desk][:endpoint]
end
