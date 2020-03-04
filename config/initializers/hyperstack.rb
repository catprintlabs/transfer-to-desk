Hyperstack.cancel_import 'react/react-source-browser' # bring your own React and ReactRouter via Yarn/Webpacker
Hyperstack.import 'hyperstack/hotloader', client_only: true if Rails.env.development?
# set the component base class

Hyperstack.component_base_class = 'HyperComponent' # i.e. 'ApplicationComponent'

Hyperstack.configuration do |config|
  config.prerendering = :off # or :on
  config.transport = :action_cable # :action_cable # or :none, :pusher,  :simple_poller
  # config.opts = {
  #   seconds_between_poll: 60
  # }
end

# add this line if you need jQuery AND ARE NOT USING WEBPACK
# Hyperstack.import 'hyperstack/component/jquery', client_only: true

# change definition of on_error to control how errors such as validation
# exceptions are reported on the server
module Hyperstack
  def self.on_error(operation, err, params, formatted_error_message)
    ::Rails.logger.debug(
      "#{formatted_error_message}\n\n" +
      Pastel.new.red(
        'To further investigate you may want to add a debugging '\
        'breakpoint to the on_error method in config/initializers/hyperstack.rb'
      )
    )
  end
end if Rails.env.development?
