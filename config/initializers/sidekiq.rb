if false
  saved = Sidekiq::Cron::Job.create(
    name: 'Transfer Desk Cases To Freshdesk',
    cron: "*/#{Freshdesk::TransferDeskCases::MINUTES_PER_TASK+1} * * * *",
    # cron: "*/1 * * * *",
    class: 'Freshdesk::TransferDeskCasesWorker'
  )

  puts "CRON JOB RUNNING... #{saved}"
end
