module Freshdesk
  class TransferDeskCasesWorker
    include Sidekiq::Worker
    def perform
      TransferDeskCases.transfer
    end
  end
end
